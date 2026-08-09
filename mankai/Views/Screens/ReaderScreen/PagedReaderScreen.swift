//
//  PagedReaderScreen.swift
//  mankai
//
//  Created by Travis XU on 7/2/2026.
//

import SwiftUI
import UIKit

private enum OverscrollType {
    case previous
    case next
}

private final class OverscrollViewController: UIViewController {
    let type: OverscrollType
    private let orientation: NavigationOrientation
    private let readingDirection: ReadingDirection
    private let availability: ReaderChapterAvailability

    init(
        type: OverscrollType,
        orientation: NavigationOrientation,
        readingDirection: ReadingDirection,
        availability: ReaderChapterAvailability
    ) {
        self.type = type
        self.orientation = orientation
        self.readingDirection = readingDirection
        self.availability = availability
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let arrow = UIImageView()
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.tintColor = .secondaryLabel
        arrow.contentMode = .scaleAspectFit
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        view.addSubview(container)
        container.addSubview(arrow)
        container.addSubview(label)

        var constraints = [
            arrow.topAnchor.constraint(equalTo: container.topAnchor),
            arrow.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 48),
            arrow.heightAnchor.constraint(equalToConstant: 48),
            label.topAnchor.constraint(equalTo: arrow.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]

        if availability != .available {
            constraints += [
                container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                container.leadingAnchor.constraint(
                    greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
                container.trailingAnchor.constraint(
                    lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            ]
        } else if orientation == .vertical {
            constraints += [
                container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                container.leadingAnchor.constraint(
                    greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
                container.trailingAnchor.constraint(
                    lessThanOrEqualTo: view.trailingAnchor, constant: -20),
                type == .previous
                    ? container.bottomAnchor.constraint(
                        equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                        constant: -40
                    )
                    : container.topAnchor.constraint(
                        equalTo: view.safeAreaLayoutGuide.topAnchor,
                        constant: 40
                    ),
            ]
        } else {
            constraints += [
                container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                container.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            ]
            let placeAtLeading = (readingDirection == .rightToLeft) == (type == .previous)
            constraints.append(
                placeAtLeading
                    ? container.leadingAnchor.constraint(
                        equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                        constant: 40
                    )
                    : container.trailingAnchor.constraint(
                        equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                        constant: -40
                    )
            )
        }

        NSLayoutConstraint.activate(constraints)
        configure(arrow: arrow, label: label)
    }

    private func configure(arrow: UIImageView, label: UILabel) {
        switch availability {
        case .unavailable:
            arrow.image = UIImage(systemName: "xmark")
            label.text =
                type == .previous
                ? String(localized: "noPreviousChapter")
                : String(localized: "noNextChapter")
        case .locked:
            arrow.image = UIImage(systemName: "lock.fill")
            label.text =
                type == .previous
                ? String(localized: "previousChapterIsLocked")
                : String(localized: "nextChapterIsLocked")
        case .available:
            if orientation == .vertical {
                arrow.image = UIImage(systemName: type == .previous ? "chevron.up" : "chevron.down")
            } else if readingDirection == .rightToLeft {
                arrow.image = UIImage(
                    systemName: type == .previous ? "chevron.right" : "chevron.left")
            } else {
                arrow.image = UIImage(
                    systemName: type == .previous ? "chevron.left" : "chevron.right")
            }
            label.text =
                type == .previous
                ? String(localized: "pullToLoadPreviousChapter")
                : String(localized: "pullToLoadNextChapter")
        }
    }
}

private final class PagedReaderViewController: UIViewController,
    UIPageViewControllerDataSource,
    UIPageViewControllerDelegate
{
    private var renderState: ReaderRenderState
    private var configuration: ReaderRenderConfiguration
    private var actions: ReaderRenderActions

    private var pageViewController: UIPageViewController!
    private var currentGroup = 0
    private var renderedRevision = -1
    private var renderedChapterID: String?
    private var lastAppliedNavigationGeneration = -1
    private var lastReportedViewportSize = CGSize.zero

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
        view.backgroundColor = .systemBackground
        createPageViewController()
        setupGestures()
        applyCurrentState(force: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let viewportSize = view.bounds.size
        if viewportSize != lastReportedViewportSize, viewportSize.width > 0, viewportSize.height > 0
        {
            lastReportedViewportSize = viewportSize
            actions.viewportDidChange(viewportSize)
        }
    }

    func apply(
        state: ReaderRenderState,
        configuration: ReaderRenderConfiguration,
        actions: ReaderRenderActions
    ) {
        let chapterChanged = renderedChapterID != state.chapterID
        let contentChanged = renderedRevision != state.revision
        let orientationChanged =
            self.configuration.navigationOrientation
            != configuration.navigationOrientation
        let directionChanged = self.configuration.readingDirection != configuration.readingDirection

        renderState = state
        self.configuration = configuration
        self.actions = actions

        guard isViewLoaded else { return }

        if chapterChanged {
            currentGroup = 0
        }

        if orientationChanged || directionChanged {
            recreatePageViewController()
        }

        if chapterChanged || contentChanged || orientationChanged || directionChanged {
            applyCurrentState(force: true)
        }

        if let command = state.navigationCommand,
            command.generation != lastAppliedNavigationGeneration
        {
            applyNavigationCommand(command)
        }
    }

    private func applyCurrentState(force: Bool) {
        guard force || renderedRevision != renderState.revision else { return }
        renderedRevision = renderState.revision
        renderedChapterID = renderState.chapterID

        guard !renderState.groups.isEmpty else {
            let placeholder = UIViewController()
            placeholder.view.backgroundColor = .systemBackground
            pageViewController.setViewControllers(
                [placeholder],
                direction: .forward,
                animated: false
            )
            return
        }

        if renderState.urls.indices.contains(renderState.currentPage) {
            let currentURL = renderState.urls[renderState.currentPage]
            if let groupIndex = renderState.groups.firstIndex(where: { $0.contains(currentURL) }) {
                currentGroup = groupIndex
            }
        }
        currentGroup = min(max(currentGroup, 0), renderState.groups.count - 1)

        if let visiblePage = pageViewController.viewControllers?.first
            as? PageContentViewController,
            visiblePage.pageIndex == currentGroup,
            visiblePage.urls == renderState.groups[currentGroup].urls
        {
            visiblePage.apply(
                images: images(for: renderState.groups[currentGroup]),
                readingDirection: configuration.readingDirection
            )
        } else {
            showGroup(currentGroup, direction: .forward, animated: false)
        }
    }

    private func createPageViewController() {
        let orientation: UIPageViewController.NavigationOrientation =
            configuration.navigationOrientation == .vertical ? .vertical : .horizontal
        pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: orientation
        )
        pageViewController.dataSource = self
        pageViewController.delegate = self
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        pageViewController.didMove(toParent: self)
    }

    private func recreatePageViewController() {
        pageViewController.willMove(toParent: nil)
        pageViewController.view.removeFromSuperview()
        pageViewController.removeFromParent()
        createPageViewController()
    }

    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        let width = view.bounds.width

        guard configuration.tapNavigation else {
            actions.toggleChrome()
            return
        }

        if location.x < width / 3 {
            if configuration.navigationOrientation == .horizontal,
                configuration.tapNavigationBehavior == .followReadingDirection,
                configuration.readingDirection == .rightToLeft
            {
                actions.requestGroupStep(.next)
            } else {
                actions.requestGroupStep(.previous)
            }
        } else if location.x > width * 2 / 3 {
            if configuration.navigationOrientation == .horizontal,
                configuration.tapNavigationBehavior == .followReadingDirection,
                configuration.readingDirection == .rightToLeft
            {
                actions.requestGroupStep(.previous)
            } else {
                actions.requestGroupStep(.next)
            }
        } else {
            actions.toggleChrome()
        }
    }

    private func applyNavigationCommand(_ command: ReaderNavigationCommand) {
        guard
            let targetGroup = renderState.groups.firstIndex(where: {
                $0.contains(command.targetURL)
            })
        else { return }

        let direction: UIPageViewController.NavigationDirection
        if configuration.navigationOrientation == .horizontal,
            configuration.readingDirection == .rightToLeft
        {
            direction = targetGroup > currentGroup ? .reverse : .forward
        } else {
            direction = targetGroup > currentGroup ? .forward : .reverse
        }

        currentGroup = targetGroup
        showGroup(targetGroup, direction: direction, animated: command.animated)
        lastAppliedNavigationGeneration = command.generation
    }

    private func showGroup(
        _ groupIndex: Int,
        direction: UIPageViewController.NavigationDirection,
        animated: Bool
    ) {
        guard renderState.groups.indices.contains(groupIndex) else { return }
        let page = makePageContentViewController(for: groupIndex)
        pageViewController.setViewControllers([page], direction: direction, animated: animated)
    }

    private func makePageContentViewController(for groupIndex: Int) -> PageContentViewController {
        guard renderState.groups.indices.contains(groupIndex) else {
            return PageContentViewController(
                pageIndex: 0,
                urls: [],
                images: [:],
                readingDirection: configuration.readingDirection
            )
        }
        let group = renderState.groups[groupIndex]
        return PageContentViewController(
            pageIndex: groupIndex,
            urls: group.urls,
            images: images(for: group),
            readingDirection: configuration.readingDirection
        )
    }

    private func images(for group: ReaderGroup) -> [String: ReaderImageState] {
        Dictionary(
            uniqueKeysWithValues: group.urls.map { url in
                (url, renderState.images[url] ?? .loading)
            }
        )
    }

    private func makeOverscrollViewController(type: OverscrollType) -> UIViewController {
        OverscrollViewController(
            type: type,
            orientation: configuration.navigationOrientation,
            readingDirection: configuration.readingDirection,
            availability: type == .previous
                ? renderState.previousChapter
                : renderState.nextChapter
        )
    }

    func pageViewController(
        _: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        adjacentViewController(to: viewController, before: true)
    }

    func pageViewController(
        _: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        adjacentViewController(to: viewController, before: false)
    }

    private func adjacentViewController(
        to viewController: UIViewController,
        before: Bool
    ) -> UIViewController? {
        guard !(viewController is OverscrollViewController),
            let content = viewController as? PageContentViewController
        else { return nil }

        let isHorizontalRTL =
            configuration.navigationOrientation == .horizontal
            && configuration.readingDirection == .rightToLeft
        let delta: Int
        if configuration.navigationOrientation == .vertical {
            delta = before ? -1 : 1
        } else if isHorizontalRTL {
            delta = before ? 1 : -1
        } else {
            delta = before ? -1 : 1
        }

        let newIndex = content.pageIndex + delta
        if newIndex < 0 {
            return makeOverscrollViewController(type: .previous)
        }
        if newIndex >= renderState.groups.count {
            return makeOverscrollViewController(type: .next)
        }
        return makePageContentViewController(for: newIndex)
    }

    func pageViewController(
        _: UIPageViewController,
        didFinishAnimating _: Bool,
        previousViewControllers _: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed, let visibleController = pageViewController.viewControllers?.first else {
            return
        }

        if let overscroll = visibleController as? OverscrollViewController {
            let availability =
                overscroll.type == .previous
                ? renderState.previousChapter
                : renderState.nextChapter
            guard availability == .available else { return }
            actions.requestChapterStep(overscroll.type == .previous ? .previous : .next)
            return
        }

        guard let page = visibleController as? PageContentViewController,
            renderState.groups.indices.contains(page.pageIndex),
            let firstURL = renderState.groups[page.pageIndex].urls.first,
            let rawPage = renderState.urls.firstIndex(of: firstURL)
        else { return }

        currentGroup = page.pageIndex
        actions.pageDidChange(rawPage)
    }
}

private final class PageContentViewController: UIViewController, UIScrollViewDelegate {
    let pageIndex: Int
    let urls: [String]
    private var images: [String: ReaderImageState]
    private var readingDirection: ReadingDirection

    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()
    private var imageViews: [String: UIImageView] = [:]
    private var imageWidthConstraints: [String: NSLayoutConstraint] = [:]
    private var loadingIndicators: [String: UIActivityIndicatorView] = [:]
    private var errorIcons: [String: UIImageView] = [:]

    init(
        pageIndex: Int,
        urls: [String],
        images: [String: ReaderImageState],
        readingDirection: ReadingDirection
    ) {
        self.pageIndex = pageIndex
        self.urls = urls
        self.images = images
        self.readingDirection = readingDirection
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContent()
    }

    func apply(images: [String: ReaderImageState], readingDirection: ReadingDirection) {
        self.images = images
        self.readingDirection = readingDirection
        guard isViewLoaded else { return }
        updateContent()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .horizontal
        contentStackView.distribution = .fill
        contentStackView.spacing = 0
        scrollView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStackView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            contentStackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])

        let orderedURLs = readingDirection == .rightToLeft ? Array(urls.reversed()) : urls
        for url in orderedURLs {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageViews[url] = imageView
            container.addSubview(imageView)

            let loadingIndicator = UIActivityIndicatorView(style: .large)
            loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
            loadingIndicator.hidesWhenStopped = true
            loadingIndicators[url] = loadingIndicator
            container.addSubview(loadingIndicator)

            let errorIconName: String
            if #available(iOS 18.0, *) {
                errorIconName = "photo.badge.exclamationmark"
            } else {
                errorIconName = "exclamationmark.circle.fill"
            }
            let errorIcon = UIImageView(image: UIImage(systemName: errorIconName))
            errorIcon.translatesAutoresizingMaskIntoConstraints = false
            errorIcon.tintColor = .secondaryLabel
            errorIcon.contentMode = .scaleAspectFit
            errorIcon.isHidden = true
            errorIcons[url] = errorIcon
            container.addSubview(errorIcon)

            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: container.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                loadingIndicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                loadingIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                errorIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                errorIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                errorIcon.widthAnchor.constraint(equalToConstant: 48),
                errorIcon.heightAnchor.constraint(equalToConstant: 48),
            ])

            let widthConstraint = container.widthAnchor.constraint(equalToConstant: 1)
            widthConstraint.isActive = true
            imageWidthConstraints[url] = widthConstraint
            contentStackView.addArrangedSubview(container)
        }

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
    }

    private func updateContent() {
        guard !urls.isEmpty else { return }
        var ratios: [String: CGFloat] = [:]
        var totalRatio: CGFloat = 0

        for url in urls {
            if case .success(let image) = images[url] {
                let ratio = image.size.width / image.size.height
                ratios[url] = ratio
                totalRatio += ratio
            }
        }

        let availableHeight = max(view.bounds.height, 1)
        let availableWidth = max(view.bounds.width, 1)

        for url in urls {
            guard let imageView = imageViews[url],
                let loadingIndicator = loadingIndicators[url],
                let errorIcon = errorIcons[url],
                let widthConstraint = imageWidthConstraints[url]
            else { continue }

            switch images[url] ?? .loading {
            case .success(let image):
                imageView.image = image
                imageView.isHidden = false
                loadingIndicator.stopAnimating()
                errorIcon.isHidden = true
                let ratio = image.size.width / image.size.height
                var imageWidth = availableHeight * ratio
                if totalRatio > 0, availableHeight * totalRatio > availableWidth {
                    imageWidth = ratio / totalRatio * availableWidth
                }
                widthConstraint.constant = imageWidth
            case .failed:
                imageView.isHidden = true
                loadingIndicator.stopAnimating()
                errorIcon.isHidden = false
                widthConstraint.constant = availableWidth / CGFloat(urls.count)
            case .loading:
                imageView.isHidden = true
                loadingIndicator.startAnimating()
                errorIcon.isHidden = true
                widthConstraint.constant = availableWidth / CGFloat(urls.count)
            }
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let location = gesture.location(in: contentStackView)
            scrollView.zoom(
                to: CGRect(x: location.x - 50, y: location.y - 50, width: 100, height: 100),
                animated: true
            )
        }
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
        contentStackView
    }
}

private struct PagedReaderViewControllerWrapper: UIViewControllerRepresentable {
    let state: ReaderRenderState
    let configuration: ReaderRenderConfiguration
    let actions: ReaderRenderActions

    func makeUIViewController(context _: Context) -> PagedReaderViewController {
        PagedReaderViewController(
            state: state,
            configuration: configuration,
            actions: actions
        )
    }

    func updateUIViewController(_ viewController: PagedReaderViewController, context _: Context) {
        viewController.apply(state: state, configuration: configuration, actions: actions)
    }
}

struct PagedReaderScreen: View {
    let state: ReaderRenderState
    let configuration: ReaderRenderConfiguration
    let actions: ReaderRenderActions

    var body: some View {
        PagedReaderViewControllerWrapper(
            state: state,
            configuration: configuration,
            actions: actions
        )
    }
}
