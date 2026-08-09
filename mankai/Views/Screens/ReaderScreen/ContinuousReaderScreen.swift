//
//  ContinuousReaderScreen.swift
//  mankai
//
//  Created by Travis XU on 30/6/2025.
//

import SwiftUI
import UIKit

private let CONTINUOUS_LOADING_IMAGE_TAG = 1
private let CONTINUOUS_ERROR_IMAGE_TAG = 2
private let CONTINUOUS_TOP_ARROW_TAG = 3
private let CONTINUOUS_TOP_TEXT_TAG = 4
private let CONTINUOUS_BOTTOM_ARROW_TAG = 5
private let CONTINUOUS_BOTTOM_TEXT_TAG = 6
private let CONTINUOUS_OVERSCROLL_THRESHOLD: CGFloat = 80

private struct ContinuousGroup: Equatable {
    let urls: [String]
    var y: CGFloat = 0
    var height: CGFloat = 0

    func contains(_ url: String) -> Bool {
        urls.contains(url)
    }
}

private final class ContinuousReaderViewController: UIViewController, UIScrollViewDelegate {
    private var renderState: ReaderRenderState
    private var configuration: ReaderRenderConfiguration
    private var actions: ReaderRenderActions

    private var groups: [ContinuousGroup] = []
    private var currentPage = 0
    private var currentGroupIndex: Int?
    private var startY: CGFloat = 0
    private var navigationBarHeight: CGFloat?
    private var renderedRevision = -1
    private var renderedChapterID: String?
    private var lastAppliedNavigationGeneration = -1
    private var pendingNavigationCommand: ReaderNavigationCommand?
    private var lastReportedViewportSize = CGSize.zero
    private var imageViews: [String: UIView] = [:]

    private var hasTriggeredTopHaptic = false
    private var hasTriggeredBottomHaptic = false
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private var isResizing = false

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let containerView = UIView()
    private let topOverscrollView = UIView()
    private let bottomOverscrollView = UIView()

    private var containerLeadingConstraint: NSLayoutConstraint!
    private var containerTopConstraint: NSLayoutConstraint!
    private var containerWidthConstraint: NSLayoutConstraint!
    private var containerHeightConstraint: NSLayoutConstraint!
    private var contentHeightConstraint: NSLayoutConstraint!

    init(
        state: ReaderRenderState,
        configuration: ReaderRenderConfiguration,
        actions: ReaderRenderActions
    ) {
        renderState = state
        self.configuration = configuration
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
        setupConstraints()
        applyCurrentState(force: true)
        enqueueNavigationCommand(from: renderState)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateImageViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let viewportSize = view.bounds.size
        if viewportSize != lastReportedViewportSize, viewportSize.width > 0, viewportSize.height > 0
        {
            lastReportedViewportSize = viewportSize
            actions.viewportDidChange(viewportSize)
        }

        applyPendingNavigationCommand()
        isResizing = false
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        isResizing = true
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.view.setNeedsLayout()
        }
    }

    func apply(
        state: ReaderRenderState,
        configuration: ReaderRenderConfiguration,
        actions: ReaderRenderActions
    ) {
        let chapterChanged = renderedChapterID != state.chapterID
        let contentChanged = renderedRevision != state.revision
        let configurationChanged = self.configuration != configuration

        renderState = state
        self.configuration = configuration
        self.actions = actions
        currentPage = state.currentPage

        guard isViewLoaded else { return }

        if chapterChanged {
            resetForChapter()
        }

        if chapterChanged || contentChanged || configurationChanged {
            applyCurrentState(force: true)
        }

        enqueueNavigationCommand(from: state)

        updateOverscrollViews()
        view.setNeedsLayout()
    }

    private func enqueueNavigationCommand(from state: ReaderRenderState) {
        guard let command = state.navigationCommand,
            command.generation != lastAppliedNavigationGeneration
        else { return }
        pendingNavigationCommand = command
    }

    private func applyCurrentState(force: Bool) {
        guard force || renderedRevision != renderState.revision else { return }
        renderedRevision = renderState.revision
        renderedChapterID = renderState.chapterID
        groups = renderState.groups.map { ContinuousGroup(urls: $0.urls) }
        removeStaleImageViews()
        updateOverscrollViews()
        view.setNeedsLayout()
    }

    private func resetForChapter() {
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        scrollView.setContentOffset(.zero, animated: false)
        imageViews.values.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()
        groups.removeAll()
        currentGroupIndex = nil
        startY = 0
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
        contentView
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isResizing else { return }

        updateCurrentPageFromScroll()

        let offsetY = scrollView.contentOffset.y
        let maximumY = max(0, scrollView.contentSize.height - scrollView.bounds.height)

        if offsetY < -CONTINUOUS_OVERSCROLL_THRESHOLD,
            !hasTriggeredTopHaptic,
            renderState.previousChapter == .available
        {
            impactFeedback.impactOccurred()
            hasTriggeredTopHaptic = true
        }

        if offsetY > maximumY + CONTINUOUS_OVERSCROLL_THRESHOLD,
            !hasTriggeredBottomHaptic,
            renderState.nextChapter == .available
        {
            impactFeedback.impactOccurred()
            hasTriggeredBottomHaptic = true
        }
    }

    func scrollViewWillBeginDragging(_: UIScrollView) {
        impactFeedback.prepare()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity _: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard configuration.snapToPage else { return }

        let zoomScale = scrollView.zoomScale
        let viewportHeight = view.bounds.height
        let viewportTop = targetContentOffset.pointee.y
        let viewportBottom = viewportTop + viewportHeight
        let viewportCenter = viewportTop + viewportHeight / 2
        var closestTargetY: CGFloat?
        var closestDistance = CGFloat.greatestFiniteMagnitude
        var shouldFreeScroll = false

        for (index, group) in groups.enumerated() {
            let groupTop = (group.y + startY) * zoomScale
            let groupHeight = group.height * zoomScale
            let groupBottom = groupTop + groupHeight
            let groupCenter = groupTop + groupHeight / 2
            var targetY: CGFloat
            var distance: CGFloat
            var freeScroll = false

            if index != currentGroupIndex || groupHeight <= viewportHeight {
                distance = abs(groupCenter - viewportCenter)
                targetY = groupCenter - viewportHeight / 2
            } else if viewportTop >= groupTop, viewportBottom <= groupBottom {
                distance = 0
                targetY = targetContentOffset.pointee.y
                freeScroll = true
            } else {
                let topDistance = abs(viewportTop - groupTop)
                let bottomDistance = abs(viewportBottom - groupBottom)
                if topDistance < bottomDistance {
                    distance = topDistance
                    targetY = groupTop
                } else {
                    distance = bottomDistance
                    targetY = groupBottom - viewportHeight
                }
            }

            if distance < closestDistance {
                closestDistance = distance
                closestTargetY = targetY
                shouldFreeScroll = freeScroll
            }
        }

        guard let closestTargetY, !shouldFreeScroll else { return }
        let maximumY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let maximumX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let targetY = max(0, min(closestTargetY, maximumY))
        let targetX = max(0, min(scrollView.contentOffset.x, maximumX))

        if configuration.softSnap {
            targetContentOffset.pointee.y = targetY
        } else {
            targetContentOffset.pointee = scrollView.contentOffset
            scrollView.setContentOffset(CGPoint(x: targetX, y: targetY), animated: true)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate _: Bool) {
        defer {
            hasTriggeredTopHaptic = false
            hasTriggeredBottomHaptic = false
        }

        let offsetY = scrollView.contentOffset.y
        let maximumY = max(0, scrollView.contentSize.height - scrollView.bounds.height)

        if offsetY < -CONTINUOUS_OVERSCROLL_THRESHOLD,
            renderState.previousChapter == .available
        {
            actions.requestChapterStep(.previous)
        } else if offsetY > maximumY + CONTINUOUS_OVERSCROLL_THRESHOLD,
            renderState.nextChapter == .available
        {
            actions.requestChapterStep(.next)
        }
    }

    private func updateCurrentPageFromScroll() {
        guard !groups.isEmpty else { return }
        let viewportCenter = scrollView.contentOffset.y + view.bounds.height / 2
        var closestIndex = 0
        var closestDistance = CGFloat.greatestFiniteMagnitude

        for (index, group) in groups.enumerated() {
            let groupCenter = (group.y + group.height / 2) * scrollView.zoomScale + startY
            let distance = abs(groupCenter - viewportCenter)
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }

        currentGroupIndex = closestIndex
        guard let firstURL = groups[closestIndex].urls.first,
            let page = renderState.urls.firstIndex(of: firstURL),
            page != currentPage
        else { return }

        currentPage = page
        actions.pageDidChange(page)
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.maximumZoomScale = 3
        scrollView.delegate = self

        contentView.translatesAutoresizingMaskIntoConstraints = false
        containerView.translatesAutoresizingMaskIntoConstraints = false
        topOverscrollView.translatesAutoresizingMaskIntoConstraints = false
        bottomOverscrollView.translatesAutoresizingMaskIntoConstraints = false
        setupOverscrollViews()

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        scrollView.addSubview(topOverscrollView)
        scrollView.addSubview(bottomOverscrollView)
        contentView.addSubview(containerView)
    }

    private func setupConstraints() {
        containerLeadingConstraint = containerView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor
        )
        containerTopConstraint = containerView.topAnchor.constraint(equalTo: contentView.topAnchor)
        containerWidthConstraint = containerView.widthAnchor.constraint(equalToConstant: 0)
        containerHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: 0)
        contentHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentHeightConstraint,

            containerLeadingConstraint,
            containerTopConstraint,
            containerWidthConstraint,
            containerHeightConstraint,

            topOverscrollView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            topOverscrollView.bottomAnchor.constraint(equalTo: scrollView.topAnchor),
            bottomOverscrollView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            bottomOverscrollView.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])
    }

    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scrollView.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: scrollView)
        let width = scrollView.bounds.width

        guard configuration.tapNavigation else {
            actions.toggleChrome()
            return
        }

        if location.x < width / 3 {
            actions.requestGroupStep(.previous)
        } else if location.x > width * 2 / 3 {
            actions.requestGroupStep(.next)
        } else {
            actions.toggleChrome()
        }
    }

    private func makePlaceholderView(child: UIView, identifierTag: Int) -> UIView {
        let wrapper = UIView()
        child.translatesAutoresizingMaskIntoConstraints = false
        child.tag = identifierTag
        wrapper.addSubview(child)
        NSLayoutConstraint.activate([
            child.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            child.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])
        return wrapper
    }

    private func view(for state: ReaderImageState) -> UIView {
        switch state {
        case .success(let image):
            let imageView = UIImageView(image: image.uiImage(retainData: true))
            imageView.contentMode = .scaleToFill
            return imageView
        case .failed:
            let errorIconName: String
            if #available(iOS 18.0, *) {
                errorIconName = "photo.badge.exclamationmark"
            } else {
                errorIconName = "exclamationmark.circle.fill"
            }
            let icon = UIImageView(image: UIImage(systemName: errorIconName))
            icon.tintColor = .secondaryLabel
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 48),
                icon.heightAnchor.constraint(equalToConstant: 48),
            ])
            return makePlaceholderView(child: icon, identifierTag: CONTINUOUS_ERROR_IMAGE_TAG)
        case .loading:
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            return makePlaceholderView(child: spinner, identifierTag: CONTINUOUS_LOADING_IMAGE_TAG)
        }
    }

    private func reconcileImageView(url: String, frame: CGRect) {
        let state = renderState.images[url] ?? .loading
        if let existingView = imageViews[url], view(existingView, matches: state) {
            existingView.frame = frame
            return
        }

        imageViews[url]?.removeFromSuperview()
        let newView = view(for: state)
        newView.frame = frame
        imageViews[url] = newView
        containerView.addSubview(newView)
    }

    private func view(_ view: UIView, matches state: ReaderImageState) -> Bool {
        switch state {
        case .success(let image):
            return (view as? UIImageView)?.image === image.uiImage(retainData: true)
        case .failed:
            return view.viewWithTag(CONTINUOUS_ERROR_IMAGE_TAG) != nil
        case .loading:
            return view.viewWithTag(CONTINUOUS_LOADING_IMAGE_TAG) != nil
        }
    }

    private func removeStaleImageViews() {
        let activeURLs = Set(renderState.urls)
        let staleURLs = imageViews.keys.filter { !activeURLs.contains($0) }
        for url in staleURLs {
            imageViews[url]?.removeFromSuperview()
            imageViews[url] = nil
        }
    }

    private func calculateImageRatios() -> [String: CGFloat] {
        renderState.images.compactMapValues { state in
            guard case .success(let image) = state else { return nil }
            return image.size.width / image.size.height
        }
    }

    private func calculateModeRatio(from ratios: [String: CGFloat]) -> CGFloat {
        guard !ratios.isEmpty else { return 1 }
        var counts: [CGFloat: Int] = [:]
        for ratio in ratios.values {
            counts[(ratio * 100).rounded() / 100, default: 0] += 1
        }
        let maximumCount = counts.values.max() ?? 0
        return counts.filter { $0.value == maximumCount }.keys.min() ?? 1
    }

    private func calculateFrames(
        ratios: [String: CGFloat],
        mode: CGFloat
    ) -> ([String: CGRect], CGFloat) {
        let width = view.safeAreaLayoutGuide.layoutFrame.width
        guard width > 0 else { return ([:], 0) }

        let isRightToLeft = configuration.readingDirection == .rightToLeft
        var frames: [String: CGRect] = [:]
        var currentY: CGFloat = 0

        for index in groups.indices {
            let groupURLs = groups[index].urls
            guard let firstURL = groupURLs.first else { continue }
            let isSinglePortrait =
                configuration.defaultGroupSize != 1
                && groupURLs.count == 1
                && ratios[firstURL, default: mode] < 1
            let effectiveWidth =
                isSinglePortrait
                ? width / CGFloat(configuration.defaultGroupSize)
                : width
            let ratioSum = groupURLs.reduce(CGFloat(0)) { result, url in
                result + ratios[url, default: mode]
            }
            let rowHeight = effectiveWidth / max(ratioSum, 0.01)
            var currentX: CGFloat = 0

            let orderedURLs = isRightToLeft ? Array(groupURLs.reversed()) : groupURLs
            for url in orderedURLs {
                let imageWidth = rowHeight * ratios[url, default: mode]
                let x = isSinglePortrait && isRightToLeft ? width - imageWidth : currentX
                frames[url] = CGRect(x: x, y: currentY, width: imageWidth, height: rowHeight)
                currentX += imageWidth
            }

            groups[index].y = currentY
            groups[index].height = rowHeight
            currentY += rowHeight
        }

        return (frames, currentY)
    }

    private func updateImageViews() {
        guard !renderState.urls.isEmpty else {
            containerHeightConstraint.constant = 0
            contentHeightConstraint.constant = max(view.bounds.height, 1)
            return
        }

        let ratios = calculateImageRatios()
        let mode = calculateModeRatio(from: ratios)
        let (frames, finalY) = calculateFrames(ratios: ratios, mode: mode)

        for url in renderState.urls {
            reconcileImageView(url: url, frame: frames[url] ?? .zero)
        }

        if navigationBarHeight == nil {
            navigationBarHeight = navigationController?.navigationBar.frame.height
        }
        startY = max(0, view.safeAreaInsets.top - (navigationBarHeight ?? 0))
        containerLeadingConstraint.constant = view.safeAreaInsets.left
        containerTopConstraint.constant = startY
        containerWidthConstraint.constant = view.safeAreaLayoutGuide.layoutFrame.width
        containerHeightConstraint.constant = finalY
        contentHeightConstraint.constant = max(
            finalY + startY + view.safeAreaInsets.bottom,
            view.bounds.height
        )
        topOverscrollView.isHidden = false
        bottomOverscrollView.isHidden = false
    }

    private func applyPendingNavigationCommand() {
        guard let command = pendingNavigationCommand,
            command.generation != lastAppliedNavigationGeneration,
            let targetPage = renderState.urls.firstIndex(of: command.targetURL),
            let groupIndex = groups.firstIndex(where: { $0.contains(command.targetURL) })
        else { return }

        let group = groups[groupIndex]
        let centerY = group.y + group.height / 2
        let scaledCenterY = centerY * scrollView.zoomScale
        let targetY = scaledCenterY + startY - view.bounds.height / 2
        let maximumY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let clampedY = max(0, min(targetY, maximumY))
        currentGroupIndex = groupIndex
        scrollView.setContentOffset(CGPoint(x: 0, y: clampedY), animated: command.animated)

        let targetGeometryIsStable = renderState.urls[...targetPage].allSatisfy { url in
            guard let image = renderState.images[url] else { return false }
            if case .loading = image { return false }
            return true
        }
        guard targetGeometryIsStable else { return }

        lastAppliedNavigationGeneration = command.generation
        pendingNavigationCommand = nil
    }

    private func setupOverscrollViews() {
        let topArrow = UIImageView()
        topArrow.translatesAutoresizingMaskIntoConstraints = false
        topArrow.tintColor = .secondaryLabel
        topArrow.contentMode = .scaleAspectFit
        topArrow.tag = CONTINUOUS_TOP_ARROW_TAG
        let topText = UILabel()
        topText.translatesAutoresizingMaskIntoConstraints = false
        topText.textColor = .secondaryLabel
        topText.textAlignment = .center
        topText.tag = CONTINUOUS_TOP_TEXT_TAG
        topOverscrollView.addSubview(topArrow)
        topOverscrollView.addSubview(topText)

        let bottomArrow = UIImageView()
        bottomArrow.translatesAutoresizingMaskIntoConstraints = false
        bottomArrow.tintColor = .secondaryLabel
        bottomArrow.contentMode = .scaleAspectFit
        bottomArrow.tag = CONTINUOUS_BOTTOM_ARROW_TAG
        let bottomText = UILabel()
        bottomText.translatesAutoresizingMaskIntoConstraints = false
        bottomText.textColor = .secondaryLabel
        bottomText.textAlignment = .center
        bottomText.tag = CONTINUOUS_BOTTOM_TEXT_TAG
        bottomOverscrollView.addSubview(bottomArrow)
        bottomOverscrollView.addSubview(bottomText)

        NSLayoutConstraint.activate([
            topArrow.topAnchor.constraint(equalTo: topOverscrollView.topAnchor, constant: 8),
            topArrow.centerXAnchor.constraint(equalTo: topOverscrollView.centerXAnchor),
            topArrow.widthAnchor.constraint(equalToConstant: 48),
            topArrow.heightAnchor.constraint(equalToConstant: 48),
            topText.topAnchor.constraint(equalTo: topArrow.bottomAnchor, constant: 8),
            topText.leadingAnchor.constraint(equalTo: topOverscrollView.leadingAnchor, constant: 8),
            topText.trailingAnchor.constraint(
                equalTo: topOverscrollView.trailingAnchor, constant: -8),
            topText.bottomAnchor.constraint(equalTo: topOverscrollView.bottomAnchor, constant: -8),

            bottomText.topAnchor.constraint(equalTo: bottomOverscrollView.topAnchor, constant: 8),
            bottomText.leadingAnchor.constraint(
                equalTo: bottomOverscrollView.leadingAnchor, constant: 8),
            bottomText.trailingAnchor.constraint(
                equalTo: bottomOverscrollView.trailingAnchor, constant: -8
            ),
            bottomArrow.topAnchor.constraint(equalTo: bottomText.bottomAnchor, constant: 8),
            bottomArrow.centerXAnchor.constraint(equalTo: bottomOverscrollView.centerXAnchor),
            bottomArrow.widthAnchor.constraint(equalToConstant: 48),
            bottomArrow.heightAnchor.constraint(equalToConstant: 48),
            bottomArrow.bottomAnchor.constraint(
                equalTo: bottomOverscrollView.bottomAnchor, constant: -8),
        ])
    }

    private func updateOverscrollViews() {
        updateOverscrollView(
            topOverscrollView,
            availability: renderState.previousChapter,
            arrowTag: CONTINUOUS_TOP_ARROW_TAG,
            textTag: CONTINUOUS_TOP_TEXT_TAG,
            availableImage: "chevron.up",
            availableText: "releaseToLoadPreviousChapter",
            lockedText: "previousChapterIsLocked",
            unavailableText: "noPreviousChapter"
        )
        updateOverscrollView(
            bottomOverscrollView,
            availability: renderState.nextChapter,
            arrowTag: CONTINUOUS_BOTTOM_ARROW_TAG,
            textTag: CONTINUOUS_BOTTOM_TEXT_TAG,
            availableImage: "chevron.down",
            availableText: "releaseToLoadNextChapter",
            lockedText: "nextChapterIsLocked",
            unavailableText: "noNextChapter"
        )
    }

    private func updateOverscrollView(
        _ overscrollView: UIView,
        availability: ReaderChapterAvailability,
        arrowTag: Int,
        textTag: Int,
        availableImage: String,
        availableText: String.LocalizationValue,
        lockedText: String.LocalizationValue,
        unavailableText: String.LocalizationValue
    ) {
        guard let arrow = overscrollView.viewWithTag(arrowTag) as? UIImageView,
            let label = overscrollView.viewWithTag(textTag) as? UILabel
        else { return }

        switch availability {
        case .available:
            arrow.image = UIImage(systemName: availableImage)
            label.text = String(localized: availableText)
        case .locked:
            arrow.image = UIImage(systemName: "lock.fill")
            label.text = String(localized: lockedText)
        case .unavailable:
            arrow.image = UIImage(systemName: "xmark")
            label.text = String(localized: unavailableText)
        }
    }
}

private struct ContinuousReaderViewControllerWrapper: UIViewControllerRepresentable {
    let state: ReaderRenderState
    let configuration: ReaderRenderConfiguration
    let actions: ReaderRenderActions

    func makeUIViewController(context _: Context) -> ContinuousReaderViewController {
        ContinuousReaderViewController(
            state: state,
            configuration: configuration,
            actions: actions
        )
    }

    func updateUIViewController(
        _ viewController: ContinuousReaderViewController,
        context _: Context
    ) {
        viewController.apply(state: state, configuration: configuration, actions: actions)
    }
}

struct ContinuousReaderScreen: View {
    let state: ReaderRenderState
    let configuration: ReaderRenderConfiguration
    let actions: ReaderRenderActions

    var body: some View {
        ContinuousReaderViewControllerWrapper(
            state: state,
            configuration: configuration,
            actions: actions
        )
    }
}
