//
//  ContinuousReaderScreen.swift
//  mankai
//
//  Created by Travis XU on 30/6/2025.
//

import Combine
import SwiftUI
import UIKit

let LOADER_VIEW_ID = 1
let ERROR_VIEW_ID = 2
let LOADING_IMAGE_VIEW_ID = 3
let ERROR_IMAGE_VIEW_ID = 4
let PAGE_INFO_BUTTON_ID = 5
let PAGE_SLIDER_ID = 6
let PREVIOUS_CHAPTER_BUTTON_ID = 7
let PREVIOUS_BUTTON_ID = 8
let NEXT_BUTTON_ID = 9
let NEXT_CHAPTER_BUTTON_ID = 10
let TOP_OVERSCROLL_ARROW_TAG = 11
let TOP_OVERSCROLL_TEXT_TAG = 12
let BOTTOM_OVERSCROLL_ARROW_TAG = 13
let BOTTOM_OVERSCROLL_TEXT_TAG = 14

let OVERSCROLL_THRESHOLD: CGFloat = 80

private struct ContinuousGroup: Identifiable, Hashable {
    let id = UUID()
    var urls: [String]
    var y: CGFloat = 0
    var height: CGFloat = 0

    func contains(_ url: String) -> Bool {
        return urls.contains(url)
    }
}

// MARK: - ContinuousReaderViewController

private final class ContinuousReaderViewController: UIViewController, UIScrollViewDelegate {
    let plugin: Plugin
    let manga: DetailedManga
    let downloadManga: DetailedManga?
    let chapterGroupIndex: Int
    let chapter: Chapter

    private var chapters: [Chapter]
    private var currentChapterIndex: Int
    private var initialPage: Int?
    private var jumpToPage: String?

    // Reader session
    private let readerSession: ReaderSession
    private var cancellables = Set<AnyCancellable>()

    // Layout groups (derived from readerSession.groups with added layout info)
    private var groups: [ContinuousGroup] = []
    private var urls: [String] {
        readerSession.urls
    }

    // Reading state variables
    private var currentPage: Int = 0
    private var currentGroup: ContinuousGroup?
    private var startY: CGFloat = 0.0

    // Haptic feedback state
    private var hasTriggeredTopHaptic = false
    private var hasTriggeredBottomHaptic = false
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    /// Suppress scroll events during resize/rotation transitions
    private var isResizing = false

    // State variables for tab bar visibility
    var isTabBarHidden = false
    var isTabBarAnimating = false

    // State variables for navigation bar and bottom bar visibility
    var isNavigationBarHidden = false
    var isNavigationBarAnimating = false

    /// Cached settings -> Computed properties
    private var tapNavigation: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.CR_tapNavigation.rawValue) as? Bool
            ?? SettingsDefaults.CR_tapNavigation
    }

    private var snapToPage: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.CR_snapToPage.rawValue) as? Bool
            ?? SettingsDefaults.CR_snapToPage
    }

    private var respectMangaReadingDirection: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.respectMangaReadingDirection.rawValue) as? Bool
            ?? SettingsDefaults.respectMangaReadingDirection
    }

    private var readingDirection: ReadingDirection {
        if respectMangaReadingDirection, let direction = manga.readingDirection {
            return direction
        }

        return ReadingDirection(
            rawValue: UserDefaults.standard.integer(forKey: SettingsKey.CR_readingDirection.rawValue)
        )
            ?? SettingsDefaults.CR_readingDirection
    }

    private var softSnap: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.CR_softSnap.rawValue) as? Bool
            ?? SettingsDefaults.CR_softSnap
    }

    // UI Components
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let containerView = UIView()
    private let bottomBar = UIView()
    private let overscrollView = UIView()
    private let bottomOverscrollView = UIView()

    // Constraint references for dynamic updates
    private var containerLeadingConstraint: NSLayoutConstraint!
    private var containerTopConstraint: NSLayoutConstraint!
    private var containerWidthConstraint: NSLayoutConstraint!
    private var containerHeightConstraint: NSLayoutConstraint!
    private var contentHeightConstraint: NSLayoutConstraint!

    init(
        plugin: Plugin, manga: DetailedManga, downloadManga: DetailedManga?, chapterGroupIndex: Int, chapter: Chapter,
        initialPage: Int?
    ) {
        self.plugin = plugin
        self.manga = manga
        self.downloadManga = downloadManga
        self.chapterGroupIndex = chapterGroupIndex
        self.chapter = chapter
        self.initialPage = initialPage

        chapters = manga.chapters.indices.contains(chapterGroupIndex)
            ? manga.chapters[chapterGroupIndex].chapters
            : []
        currentChapterIndex = chapters.firstIndex(where: { $0.id == chapter.id }) ?? -1

        readerSession = ReaderSession(
            plugin: plugin,
            manga: manga,
            downloadManga: downloadManga
        )

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

        loadChapter()

        // Observe specific UserDefaults keys that affect layout
        UserDefaults.standard.addObserver(
            self,
            forKeyPath: SettingsKey.CR_readingDirection.rawValue,
            options: [.new],
            context: nil
        )

        UserDefaults.standard.addObserver(
            self,
            forKeyPath: SettingsKey.respectMangaReadingDirection.rawValue,
            options: [.new],
            context: nil
        )

        // Initialize settings
        readerSession.readingDirection = readingDirection

        // Subscribe to ReaderSession changes
        readerSession.$images
            .combineLatest(readerSession.$groups)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.syncGroupsFromSession()
            }
            .store(in: &cancellables)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        UserDefaults.standard.removeObserver(
            self, forKeyPath: SettingsKey.CR_readingDirection.rawValue
        )
        UserDefaults.standard.removeObserver(
            self, forKeyPath: SettingsKey.respectMangaReadingDirection.rawValue
        )

        saveTimer?.invalidate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        forceSaveRecord()
        showTabBar()
        showNavigationBar()

        Task {
            try? await SyncService.shared.sync()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        hideTabBar()

        parent?.title = chapter.title ?? chapter.id
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateImageViews()
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
        return contentView
    }

    // MARK: - Observer

    override func observeValue(
        forKeyPath keyPath: String?,
        of _: Any?,
        change _: [NSKeyValueChangeKey: Any]?,
        context _: UnsafeMutableRawPointer?
    ) {
        if keyPath == SettingsKey.CR_readingDirection.rawValue
            || keyPath == SettingsKey.respectMangaReadingDirection.rawValue
        {
            updateGrouping()
        }
    }

    private func updateGrouping() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.readerSession.readingDirection = self.readingDirection
            self.syncGroupsFromSession()
            self.navigateToPage(self.currentPage, animated: false)
            self.isResizing = false
        }
    }

    private func updateGroupingForSizeChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.readerSession.updateGrouping()
            self.syncGroupsFromSession()
            self.navigateToPage(self.currentPage, animated: false)
            self.isResizing = false
        }
    }

    override func viewWillTransition(
        to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)

        isResizing = true
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateGroupingForSizeChange()
        }
    }

    // MARK: - Scroll Event Monitoring

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isResizing else { return }

        updateCurrentPageFromScroll()

        let offsetY = scrollView.contentOffset.y
        let maxScrollY =
            max(0, scrollView.contentSize.height - scrollView.bounds.height) + OVERSCROLL_THRESHOLD

        // Trigger haptic feedback when reaching top threshold
        if offsetY < -OVERSCROLL_THRESHOLD {
            if !hasTriggeredTopHaptic, currentChapterIndex > 0 {
                impactFeedback.impactOccurred()
                hasTriggeredTopHaptic = true
            }
        }

        // Trigger haptic feedback when reaching bottom threshold
        if offsetY > maxScrollY {
            if !hasTriggeredBottomHaptic, currentChapterIndex < chapters.count - 1 {
                impactFeedback.impactOccurred()
                hasTriggeredBottomHaptic = true
            }
        }
    }

    func scrollViewWillBeginDragging(_: UIScrollView) {
        // Prepare haptic feedback for smooth response
        impactFeedback.prepare()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity _: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard snapToPage else { return }

        let zoomScale = scrollView.zoomScale
        let viewportHeight = view.bounds.height

        let viewportTop = targetContentOffset.pointee.y
        let viewportBottom = viewportTop + viewportHeight
        let viewportCenter = viewportTop + (viewportHeight / 2)

        var closestGroupScrollY: CGFloat?
        var closestDistance = CGFloat.greatestFiniteMagnitude
        var shouldFreeScroll = false

        for group in groups {
            let groupTop = (group.y + startY) * zoomScale
            let groupHeight = group.height * zoomScale
            let groupBottom = groupTop + groupHeight
            let groupCenter = groupTop + groupHeight / 2

            var distance: CGFloat = 0
            var targetY: CGFloat = 0
            var isFreeScroll = false

            if group != currentGroup || groupHeight <= viewportHeight {
                // Snap to Center
                distance = abs(groupCenter - viewportCenter)
                targetY = groupCenter - (viewportHeight / 2)
            } else {
                // Long group AND same group: Smart logic (Free Scroll / Edge Snap)
                if viewportTop >= groupTop, viewportBottom <= groupBottom {
                    // Free scroll: Maintain current projection
                    distance = 0
                    isFreeScroll = true
                    targetY = targetContentOffset.pointee.y
                } else {
                    // Snap to nearest edge
                    let distTop = abs(viewportTop - groupTop)
                    let distBottom = abs(viewportBottom - groupBottom)

                    if distTop < distBottom {
                        distance = distTop
                        targetY = groupTop
                    } else {
                        distance = distBottom
                        targetY = groupBottom - viewportHeight
                    }
                }
            }

            if distance < closestDistance {
                closestDistance = distance
                closestGroupScrollY = targetY
                shouldFreeScroll = isFreeScroll
            }
        }

        if let clampedClosestGroupScrollY = closestGroupScrollY {
            if shouldFreeScroll {
                return
            }

            let maxScrollY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let maxScrollX = max(0, scrollView.contentSize.width - scrollView.bounds.width)

            let clampedY = max(0, min(clampedClosestGroupScrollY, maxScrollY))
            let clampedX = max(0, min(scrollView.contentOffset.x, maxScrollX))

            if softSnap {
                targetContentOffset.pointee.y = clampedY
            } else {
                targetContentOffset.pointee.y = scrollView.contentOffset.y
                targetContentOffset.pointee.x = scrollView.contentOffset.x

                scrollView.setContentOffset(
                    CGPoint(x: clampedX, y: clampedY),
                    animated: true
                )
            }
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // Reset haptic feedback state when user ends dragging
        hasTriggeredTopHaptic = false
        hasTriggeredBottomHaptic = false

        guard decelerate else { return }

        let offsetY = scrollView.contentOffset.y
        let maxScrollY =
            max(0, scrollView.contentSize.height - scrollView.bounds.height) + OVERSCROLL_THRESHOLD

        if offsetY < -OVERSCROLL_THRESHOLD {
            if currentChapterIndex > 0 {
                let previousChapter = chapters[currentChapterIndex - 1]
                if previousChapter.locked != true {
                    currentChapterIndex -= 1
                    initialPage = -1
                    loadChapter()
                }
            }
        } else if offsetY > maxScrollY {
            if currentChapterIndex < chapters.count - 1 {
                let nextChapter = chapters[currentChapterIndex + 1]
                if nextChapter.locked != true {
                    currentChapterIndex += 1
                    initialPage = 0
                    loadChapter()
                }
            }
        }
    }

    private func updateCurrentPageFromScroll() {
        let zoomScale = scrollView.zoomScale
        let scrollY = scrollView.contentOffset.y + startY

        // Find which group is currently in the center of the viewport
        let viewportCenter = scrollY + (view.bounds.height / 2)

        var closestGroup: ContinuousGroup?
        var closestDistance = CGFloat.greatestFiniteMagnitude

        for group in groups {
            let centerY = group.y + group.height / 2
            let scaledCenterY = centerY * zoomScale
            let distance = abs(scaledCenterY - viewportCenter)
            if distance < closestDistance {
                closestDistance = distance
                closestGroup = group
            }
        }

        currentGroup = closestGroup

        // Update current page to the last page in the closest group
        if let closestGroup = closestGroup, let firstUrl = closestGroup.urls.first,
           let pageIndex = urls.firstIndex(of: firstUrl), pageIndex != currentPage
        {
            currentPage = pageIndex
            updateBottomBar()
            saveRecord()
        }
    }

    // MARK: - Record

    private var lastSavedPage: Int = -1
    private var saveTimer: Timer?

    private func saveRecord() {
        guard currentChapterIndex >= 0, currentChapterIndex < chapters.count else { return }

        if saveTimer != nil { return }

        saveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.performSave()
            self?.saveTimer = nil
        }
    }

    private func performSave() {
        guard currentChapterIndex >= 0, currentChapterIndex < chapters.count else { return }
        if currentPage == lastSavedPage { return }

        let currentChapter = chapters[currentChapterIndex]

        // Create manga info
        let mangaInfo: String
        if let mangaData = try? JSONEncoder().encode(manga) {
            mangaInfo = String(data: mangaData, encoding: .utf8) ?? "{}"
        } else {
            mangaInfo = "{}"
        }

        let mangaModel = MangaModel(
            mangaId: manga.id,
            pluginId: plugin.id,
            info: mangaInfo
        )

        let recordModel = RecordModel(
            mangaId: manga.id,
            pluginId: plugin.id,
            datetime: Date(),
            chapterId: currentChapter.id,
            chapterTitle: currentChapter.title,
            page: currentPage,
            shouldSync: plugin.shouldSync
        )

        Task {
            do {
                let _ = try await HistoryService.shared.add(record: recordModel, manga: mangaModel)
                lastSavedPage = currentPage
            } catch {
                Logger.ui.error("Failed to save record")
            }
        }
    }

    private func forceSaveRecord() {
        saveTimer?.invalidate()
        saveTimer = nil
        performSave()
    }

    // MARK: - Load Chapter

    private func loadChapter() {
        guard currentChapterIndex >= 0, currentChapterIndex < chapters.count else {
            showErrorView()
            return
        }

        // Reset UI
        scrollView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        containerView.subviews.forEach { $0.removeFromSuperview() }
        updateOverscrollViewsVisibility()
        bottomOverscrollView.isHidden = true
        overscrollView.isHidden = true

        // Reset state
        groups = []
        currentPage = 0
        startY = 0.0
        jumpToPage = nil

        let chapter = chapters[currentChapterIndex]
        // Set title
        parent?.title = chapter.title ?? chapter.id

        if chapter.locked == true {
            showErrorView()
            return
        }

        showLoadingView()

        Task {
            do {
                try await readerSession.getChapter(chapter: chapter)

                if var initialPage = self.initialPage {
                    if initialPage == -1 {
                        initialPage = urls.count - 1
                        self.initialPage = initialPage
                    }

                    if initialPage >= 0 && initialPage < urls.count {
                        self.jumpToPage = urls[initialPage]
                    }
                }

                updateBottomBar()
            } catch {
                showErrorView()
            }
        }
    }

    // MARK: - Sync Groups from ReaderSession

    private func syncGroupsFromSession() {
        groups = readerSession.groups.map { ContinuousGroup(urls: $0.urls) }
        updateImageViews()

        if let initialPage = initialPage, initialPage >= 0, initialPage < urls.count {
            let allImagesLoaded = (0 ... initialPage).allSatisfy { index in
                let url = urls[index]
                if let readerImage = readerSession.images[url],
                   case .success = readerImage.state
                {
                    return true
                }
                return false
            }

            navigateToPage(initialPage)

            if allImagesLoaded {
                self.initialPage = nil
                jumpToPage = nil
            }
        }
    }

    // MARK: - Page Management

    private func navigateToPage(_ page: Int, animated: Bool = false) {
        guard page >= 0, page < urls.count else { return }

        let targetUrl = urls[page]

        // Find the group containing this page
        if let groupIndex = groups.firstIndex(where: { $0.contains(targetUrl) }) {
            navigateToGroup(groupIndex, animated: animated)
        }
    }

    private func navigateToGroup(_ groupIndex: Int, animated: Bool = false) {
        guard groupIndex >= 0, groupIndex < groups.count else { return }

        let group = groups[groupIndex]

        let centerY = group.y + group.height / 2
        let scaledCenterY = centerY * scrollView.zoomScale
        let targetScrollY = scaledCenterY + startY - (view.bounds.height / 2)

        // Limit scroll position to valid bounds
        let maxScrollY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let clampedScrollY = max(0, min(targetScrollY, maxScrollY))

        scrollView.setContentOffset(
            CGPoint(x: 0, y: clampedScrollY),
            animated: animated
        )
    }

    // MARK: - Tab Bar

    private func hideTabBar() {
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(true, animated: true)
        } else {
            guard let tabBar = tabBarController?.tabBar else { return }
            if isTabBarAnimating || isTabBarHidden { return }
            isTabBarAnimating = true

            DispatchQueue.main.async {
                if let tabBarControllerView = self.tabBarController?.view {
                    tabBarControllerView.frame = CGRect(
                        x: tabBarControllerView.frame.origin.x,
                        y: tabBarControllerView.frame.origin.y,
                        width: tabBarControllerView.frame.width,
                        height: UIApplication.windowBounds.height + tabBar.frame.height
                    )
                }
            }

            UIView.animate(
                withDuration: 0.2, delay: 0, options: [.curveEaseIn],
                animations: {
                    tabBar.frame.origin.y = UIApplication.windowBounds.height
                    tabBar.alpha = 0.0
                    self.view.layoutIfNeeded()
                }
            ) { _ in
                tabBar.isHidden = true
                self.isTabBarAnimating = false
            }
            isTabBarHidden = true
        }
    }

    private func showTabBar() {
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(false, animated: true)
        } else {
            guard let tabBar = tabBarController?.tabBar else { return }
            tabBar.isHidden = false
            if isTabBarAnimating || !isTabBarHidden { return }

            isTabBarAnimating = true

            // Spring animation for a playful bounce
            UIView.animate(
                withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6,
                initialSpringVelocity: 1.0, options: [.curveEaseOut],
                animations: {
                    tabBar.frame.origin.y = UIApplication.windowBounds.height - tabBar.frame.height
                    tabBar.alpha = 1.0
                    self.view.layoutIfNeeded()
                }
            ) { _ in
                self.isTabBarAnimating = false
            }
            isTabBarHidden = false
        }
    }

    // MARK: - Navigation Bar

    func hideNavigationBar() {
        guard let navigationBar = navigationController?.navigationBar else { return }

        if isNavigationBarAnimating || isNavigationBarHidden { return }
        isNavigationBarAnimating = true

        UIView.animate(
            withDuration: 0.2, delay: 0, options: [.curveLinear],
            animations: {
                navigationBar.transform = .init(
                    translationX: 0, y: -(navigationBar.frame.height + navigationBar.frame.origin.y)
                )

                self.bottomBar.transform = .init(
                    translationX: 0, y: self.bottomBar.frame.height
                )

                self.view.layoutIfNeeded()
            }
        ) { _ in
            self.isNavigationBarAnimating = false
        }

        isNavigationBarHidden = true
    }

    func showNavigationBar() {
        guard let navigationBar = navigationController?.navigationBar else { return }

        if isNavigationBarAnimating || !isNavigationBarHidden { return }

        isNavigationBarAnimating = true

        UIView.animate(
            withDuration: 0.2, delay: 0, options: [.curveLinear],
            animations: {
                navigationBar.transform = .init(translationX: 0, y: 0)

                // Show bottom bar as well
                self.bottomBar.transform = .init(translationX: 0, y: 0)

                self.view.layoutIfNeeded()
            }
        ) { _ in
            self.isNavigationBarAnimating = false
        }

        isNavigationBarHidden = false
    }

    // MARK: - Gestures

    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(
            target: self, action: #selector(handleScreenTap(_:))
        )
        scrollView.addGestureRecognizer(tapGesture)
    }

    @objc private func handleScreenTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: scrollView)
        let width = scrollView.bounds.width

        // If tap navigation is disabled, only toggle navigation bar
        if !tapNavigation {
            if isNavigationBarHidden {
                showNavigationBar()
            } else {
                hideNavigationBar()
            }

            return
        }

        if location.x < width / 3 {
            // Left third: previous group
            let tappedGroupIndex = findGroupIndex(atY: location.y)
            navigateToGroup(tappedGroupIndex - 1, animated: true)
        } else if location.x > width * 2 / 3 {
            // Right third: next group
            let tappedGroupIndex = findGroupIndex(atY: location.y)
            navigateToGroup(tappedGroupIndex + 1, animated: true)
        } else {
            // Middle third: toggle navigation bar
            if isNavigationBarHidden {
                showNavigationBar()
            } else {
                hideNavigationBar()
            }
        }
    }

    private func findGroupIndex(atY y: CGFloat) -> Int {
        let zoomScale = scrollView.zoomScale
        let adjustedY = y - startY

        var closestGroupIndex = 0
        var closestDistance = CGFloat.greatestFiniteMagnitude

        for (index, group) in groups.enumerated() {
            let centerY = group.y + group.height / 2
            let scaledCenterY = centerY * zoomScale
            let distance = abs(scaledCenterY - adjustedY)

            if distance < closestDistance {
                closestDistance = distance
                closestGroupIndex = index
            }
        }

        return closestGroupIndex
    }

    private func findGroupIndex(forPage page: Int) -> Int {
        guard page >= 0, page < urls.count else { return 0 }

        let targetUrl = urls[page]

        for (index, group) in groups.enumerated() {
            if group.contains(targetUrl) {
                return index
            }
        }

        return 0
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Configure scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.maximumZoomScale = 3
        scrollView.delegate = self

        // Configure overscroll view
        overscrollView.translatesAutoresizingMaskIntoConstraints = false
        setupOverscrollView()

        // Configure bottom overscroll view
        bottomOverscrollView.translatesAutoresizingMaskIntoConstraints = false
        setupBottomOverscrollView()

        // Configure content view
        contentView.translatesAutoresizingMaskIntoConstraints = false

        // Configure container view
        containerView.translatesAutoresizingMaskIntoConstraints = false

        // Add views to hierarchy
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        scrollView.addSubview(overscrollView)
        scrollView.addSubview(bottomOverscrollView)
        contentView.addSubview(containerView)

        // Configure bottom bar
        setupBottomBar()
    }

    private func setupConstraints() {
        // Create container constraints with references
        containerLeadingConstraint = containerView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor
        )
        containerTopConstraint = containerView.topAnchor.constraint(equalTo: contentView.topAnchor)
        containerWidthConstraint = containerView.widthAnchor.constraint(equalToConstant: 0)
        containerHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: 0)

        // Create content height constraint with reference
        contentHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            // Scroll view constraints
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Content view constraints
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentHeightConstraint,

            // Container view constraints
            containerLeadingConstraint,
            containerTopConstraint,
            containerWidthConstraint,
            containerHeightConstraint,

            // Overscroll view constraints
            overscrollView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            overscrollView.bottomAnchor.constraint(equalTo: scrollView.topAnchor),

            // Bottom overscroll view constraints
            bottomOverscrollView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            bottomOverscrollView.topAnchor.constraint(equalTo: scrollView.bottomAnchor),

            // Bottom bar constraints
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Loading View

    private func showLoadingView() {
        view.viewWithTag(ERROR_VIEW_ID)?.removeFromSuperview()
        guard view.viewWithTag(LOADER_VIEW_ID) == nil else { return }

        // Create activity indicator
        let activityIndicator = UIActivityIndicatorView()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        activityIndicator.tag = LOADER_VIEW_ID

        view.addSubview(activityIndicator)

        // Set up constraints
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Error View

    private func showErrorView() {
        view.viewWithTag(LOADER_VIEW_ID)?.removeFromSuperview()
        guard view.viewWithTag(ERROR_VIEW_ID) == nil else { return }

        // Create error container
        let errorContainer = UIView()
        errorContainer.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.tag = ERROR_VIEW_ID

        // Create error icon
        let errorIcon = UIImageView()
        errorIcon.image = UIImage(systemName: "exclamationmark.circle")
        errorIcon.tintColor = .secondaryLabel
        errorIcon.translatesAutoresizingMaskIntoConstraints = false

        // Create error label
        let errorLabel = UILabel()
        errorLabel.text = String(localized: "failedToLoadChapter")
        errorLabel.textColor = .secondaryLabel
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.translatesAutoresizingMaskIntoConstraints = false

        // Create retry label
        let retryLabel = UILabel()
        retryLabel.text = String(localized: "tapToRetry")
        retryLabel.textColor = .secondaryLabel
        retryLabel.textAlignment = .center
        retryLabel.translatesAutoresizingMaskIntoConstraints = false

        // Add subviews
        errorContainer.addSubview(errorIcon)
        errorContainer.addSubview(errorLabel)
        errorContainer.addSubview(retryLabel)
        view.addSubview(errorContainer)

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(retryLoadChapter))
        errorContainer.addGestureRecognizer(tapGesture)
        errorContainer.isUserInteractionEnabled = true

        // Set up constraints
        NSLayoutConstraint.activate([
            errorContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            errorContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            errorIcon.topAnchor.constraint(equalTo: errorContainer.topAnchor),
            errorIcon.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),
            errorIcon.widthAnchor.constraint(equalToConstant: 48),
            errorIcon.heightAnchor.constraint(equalToConstant: 48),

            errorLabel.topAnchor.constraint(equalTo: errorIcon.bottomAnchor, constant: 20),
            errorLabel.leadingAnchor.constraint(equalTo: errorContainer.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: errorContainer.trailingAnchor),

            retryLabel.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 8),
            retryLabel.leadingAnchor.constraint(equalTo: errorContainer.leadingAnchor),
            retryLabel.trailingAnchor.constraint(equalTo: errorContainer.trailingAnchor),
            retryLabel.bottomAnchor.constraint(equalTo: errorContainer.bottomAnchor),
        ])
    }

    @objc private func retryLoadChapter() {
        loadChapter()
    }

    // MARK: - Image View Factories

    private func makePlaceholderView(
        child: UIView, identifierTag: Int
    ) -> UIView {
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

    private func createErrorImageView() -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "photo.badge.exclamationmark"))
        icon.tintColor = .secondaryLabel
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
        ])
        return makePlaceholderView(child: icon, identifierTag: ERROR_IMAGE_VIEW_ID)
    }

    private func createLoadingImageView() -> UIView {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        return makePlaceholderView(child: spinner, identifierTag: LOADING_IMAGE_VIEW_ID)
    }

    // MARK: - Image View Management

    private func viewForState(_ state: ReaderImageState) -> UIView {
        switch state {
        case let .success(uiImage):
            let imageView = UIImageView(image: uiImage)
            imageView.contentMode = .scaleToFill
            return imageView
        case .failed:
            return createErrorImageView()
        case .loading:
            return createLoadingImageView()
        }
    }

    private func stateTag(for state: ReaderImageState) -> Int? {
        switch state {
        case .success: nil
        case .failed: ERROR_IMAGE_VIEW_ID
        case .loading: LOADING_IMAGE_VIEW_ID
        }
    }

    private func tagForUrl(_ url: String) -> Int {
        var hasher = Hasher()
        hasher.combine(url)
        return hasher.finalize()
    }

    /// Reconciles the view for a single image URL against the current state.
    private func reconcileImageView(url: String, frames: [String: CGRect]) {
        let tag = tagForUrl(url)
        let state = readerSession.images[url]?.state ?? .loading
        let frame = frames[url] ?? .zero

        if let existing = containerView.viewWithTag(tag) {
            // Check if the existing view already matches the desired state
            let alreadyCorrect: Bool = {
                switch state {
                case let .success(uiImage):
                    return (existing as? UIImageView)?.image === uiImage
                case .failed:
                    return existing.viewWithTag(ERROR_IMAGE_VIEW_ID) != nil
                case .loading:
                    return existing.viewWithTag(LOADING_IMAGE_VIEW_ID) != nil
                }
            }()

            if alreadyCorrect {
                existing.frame = frame
            } else {
                existing.removeFromSuperview()
                let newView = viewForState(state)
                newView.tag = tag
                newView.frame = frame
                containerView.addSubview(newView)
            }
        } else {
            let newView = viewForState(state)
            newView.tag = tag
            newView.frame = frame
            containerView.addSubview(newView)
        }
    }

    // MARK: - Layout Calculations

    private func calculateImageRatios() -> [String: CGFloat] {
        readerSession.images.compactMapValues { readerImage in
            if case let .success(image) = readerImage.state {
                return image.size.width / image.size.height
            }
            return nil
        }
    }

    /// Returns the most common (mode) aspect ratio, rounded to 2 decimal places.
    private func calculateModeRatio(from ratios: [String: CGFloat]) -> CGFloat {
        guard !ratios.isEmpty else { return 1 }

        var counts: [CGFloat: Int] = [:]
        for value in ratios.values {
            let rounded = (value * 100).rounded() / 100
            counts[rounded, default: 0] += 1
        }

        let maxCount = counts.values.max() ?? 0
        return counts
            .filter { $0.value == maxCount }
            .keys
            .min() ?? 1
    }

    private func calculateFrames(
        ratios: [String: CGFloat], mode: CGFloat
    ) -> ([String: CGRect], CGFloat) {
        guard let window = view.window else { return ([:], 0) }

        let width = window.safeAreaLayoutGuide.layoutFrame.width
        let isRTL = readingDirection == .rightToLeft
        var frames: [String: CGRect] = [:]
        var currentY: CGFloat = 0

        for index in groups.indices {
            let groupUrls = groups[index].urls

            let isSinglePortrait =
                readerSession.defaultGroupSize != 1
                    && groupUrls.count == 1
                    && ratios[groupUrls[0], default: mode] < 1

            let effectiveWidth = isSinglePortrait ? width / CGFloat(readerSession.defaultGroupSize) : width
            let ratiosSum = groupUrls.reduce(CGFloat(0)) { $0 + ratios[$1, default: mode] }
            let rowHeight = effectiveWidth / ratiosSum

            var currentX: CGFloat = 0
            let orderedUrls = isRTL ? groupUrls.reversed() : groupUrls

            for url in orderedUrls {
                let imageWidth = rowHeight * ratios[url, default: mode]

                let xPosition: CGFloat
                if isSinglePortrait {
                    xPosition = isRTL ? width - imageWidth : 0
                } else {
                    xPosition = currentX
                }

                frames[url] = CGRect(x: xPosition, y: currentY, width: imageWidth, height: rowHeight)
                currentX += imageWidth
            }

            groups[index].y = currentY
            groups[index].height = rowHeight
            currentY += rowHeight
        }

        return (frames, currentY)
    }

    // MARK: - Image Views

    private func updateContentSize(finalY: CGFloat) {
        guard let navigationBar = navigationController?.navigationBar else { return }
        startY = view.safeAreaInsets.top - navigationBar.frame.height

        containerLeadingConstraint.constant = view.safeAreaInsets.left
        containerTopConstraint.constant = startY
        containerWidthConstraint.constant = view.safeAreaLayoutGuide.layoutFrame.width
        containerHeightConstraint.constant = finalY
        contentHeightConstraint.constant = finalY + startY + view.safeAreaInsets.bottom

        if overscrollView.isHidden {
            overscrollView.isHidden = false
            bottomOverscrollView.isHidden = false
        }

        view.layoutIfNeeded()
    }

    private func updateImageViews() {
        guard !readerSession.images.isEmpty else { return }

        // Remove full-screen loading / error overlays
        view.viewWithTag(LOADER_VIEW_ID)?.removeFromSuperview()
        view.viewWithTag(ERROR_VIEW_ID)?.removeFromSuperview()

        let ratios = calculateImageRatios()
        let mode = calculateModeRatio(from: ratios)
        let (frames, finalY) = calculateFrames(ratios: ratios, mode: mode)

        for url in urls {
            reconcileImageView(url: url, frames: frames)
        }

        updateContentSize(finalY: finalY)
    }

    // MARK: - Bottom Bar

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            let glassEffectView = UIVisualEffectView(effect: glassEffect)
            glassEffectView.frame = bottomBar.bounds
            glassEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            // Add glass effect as background
            bottomBar.addSubview(glassEffectView)

            // Make bottomBar corners rounded
            bottomBar.layer.cornerRadius = 25
            bottomBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            bottomBar.layer.masksToBounds = true
        } else {
            // Create blur effect view
            let blurEffect = UIBlurEffect(style: .systemMaterial)
            let blurEffectView = UIVisualEffectView(effect: blurEffect)
            blurEffectView.frame = bottomBar.bounds
            blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            // Add blur effect as background
            bottomBar.addSubview(blurEffectView)

            // Add a subtle border at the top
            let borderLayer = CALayer()
            borderLayer.backgroundColor = UIColor.separator.cgColor
            borderLayer.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 0.5)
            bottomBar.layer.addSublayer(borderLayer)
        }

        // Create horizontal stack view for bottom bar controls
        let bottomStackView = UIStackView()
        bottomStackView.translatesAutoresizingMaskIntoConstraints = false
        bottomStackView.axis = .horizontal
        bottomStackView.distribution = .fillProportionally
        bottomStackView.alignment = .center

        // Add control buttons
        let pageInfoButton = createBottomBarButton(title: "1 / 1")
        pageInfoButton.tag = PAGE_INFO_BUTTON_ID

        let previousChapterButton = createBottomBarButton(systemImage: "chevron.left.to.line")
        previousChapterButton.tag = PREVIOUS_CHAPTER_BUTTON_ID
        previousChapterButton.isEnabled = false

        let previousButton = createBottomBarButton(systemImage: "chevron.left")
        previousButton.tag = PREVIOUS_BUTTON_ID
        previousChapterButton.isEnabled = false

        let nextButton = createBottomBarButton(systemImage: "chevron.right")
        nextButton.tag = NEXT_BUTTON_ID
        previousChapterButton.isEnabled = currentChapterIndex > 0

        let nextChapterButton = createBottomBarButton(systemImage: "chevron.right.to.line")
        nextChapterButton.tag = NEXT_CHAPTER_BUTTON_ID
        nextChapterButton.isEnabled = currentChapterIndex < chapters.count - 1

        // Add button actions
        previousChapterButton.addTarget(
            self, action: #selector(previousChapterButtonTapped), for: .touchUpInside
        )
        previousButton.addTarget(self, action: #selector(previousButtonTapped), for: .touchUpInside)
        pageInfoButton.addTarget(self, action: #selector(pageInfoButtonTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        nextChapterButton.addTarget(
            self, action: #selector(nextChapterButtonTapped), for: .touchUpInside
        )

        bottomStackView.addArrangedSubview(previousChapterButton)
        bottomStackView.addArrangedSubview(previousButton)
        bottomStackView.addArrangedSubview(pageInfoButton)
        bottomStackView.addArrangedSubview(nextButton)
        bottomStackView.addArrangedSubview(nextChapterButton)

        bottomBar.addSubview(bottomStackView)

        // Create slider for page navigation
        let pageSlider = UISlider()
        pageSlider.tag = PAGE_SLIDER_ID
        pageSlider.translatesAutoresizingMaskIntoConstraints = false
        pageSlider.minimumValue = 1
        pageSlider.maximumValue = 1
        pageSlider.value = 1
        pageSlider.addTarget(self, action: #selector(pageSliderValueChanged), for: .valueChanged)

        bottomBar.addSubview(pageSlider)

        // Layout constraints for bottom stack view and slider
        NSLayoutConstraint.activate([
            bottomStackView.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 20),
            bottomStackView.leadingAnchor.constraint(
                equalTo: bottomBar.leadingAnchor, constant: 20
            ),
            bottomStackView.trailingAnchor.constraint(
                equalTo: bottomBar.trailingAnchor, constant: -20
            ),

            pageSlider.topAnchor.constraint(equalTo: bottomStackView.bottomAnchor, constant: 10),
            pageSlider.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            pageSlider.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            pageSlider.bottomAnchor.constraint(
                equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -20
            ),
        ])

        view.addSubview(bottomBar)
    }

    private func createBottomBarButton(title: String? = nil, systemImage: String? = nil) -> UIButton {
        var configuration = UIButton.Configuration.borderless()
        configuration.title = title
        configuration.titleLineBreakMode = .byTruncatingTail

        if let systemImage = systemImage {
            configuration.image = UIImage(systemName: systemImage)
        }

        return UIButton(configuration: configuration)
    }

    private func updateBottomBar() {
        guard let pageInfoButton = bottomBar.viewWithTag(PAGE_INFO_BUTTON_ID) as? UIButton,
              let previousChapterButton = bottomBar.viewWithTag(PREVIOUS_CHAPTER_BUTTON_ID)
              as? UIButton,
              let previousButton = bottomBar.viewWithTag(PREVIOUS_BUTTON_ID) as? UIButton,
              let nextButton = bottomBar.viewWithTag(NEXT_BUTTON_ID) as? UIButton,
              let nextChapterButton = bottomBar.viewWithTag(NEXT_CHAPTER_BUTTON_ID) as? UIButton,
              let pageSlider = bottomBar.viewWithTag(PAGE_SLIDER_ID) as? UISlider
        else {
            return
        }

        let totalPages = urls.count
        pageInfoButton.setTitle("\(currentPage + 1) / \(totalPages)", for: .normal)
        previousButton.isEnabled = currentPage != 0
        nextButton.isEnabled = currentPage < urls.count - 1

        if currentChapterIndex > 0 {
            let previousChapter = chapters[currentChapterIndex - 1]
            previousChapterButton.isEnabled = previousChapter.locked != true
        } else {
            previousChapterButton.isEnabled = false
        }

        if currentChapterIndex < chapters.count - 1 {
            let nextChapter = chapters[currentChapterIndex + 1]
            nextChapterButton.isEnabled = nextChapter.locked != true
        } else {
            nextChapterButton.isEnabled = false
        }

        pageSlider.maximumValue = Float(totalPages)
        pageSlider.value = Float(currentPage + 1)
    }

    // MARK: - Bottom Bar Actions

    @objc private func previousChapterButtonTapped() {
        currentChapterIndex -= 1
        initialPage = -1
        loadChapter()
    }

    @objc private func previousButtonTapped() {
        navigateToPage(currentPage - 1)
    }

    @objc private func pageInfoButtonTapped() {
        let chaptersModal = ChaptersModal(
            plugin: plugin,
            manga: manga,
            chapterGroupIndex: chapterGroupIndex
        ) { [weak self] chapter, _, _ in
            guard let self = self else { return }

            if let index = self.chapters.firstIndex(where: { $0.id == chapter.id }) {
                self.currentChapterIndex = index
                self.loadChapter()
                self.presentedViewController?.dismiss(animated: true)
            }
        }

        let hostingController = UIHostingController(rootView: chaptersModal)
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }

        present(hostingController, animated: true)
    }

    @objc private func nextButtonTapped() {
        navigateToPage(currentPage + 1)
    }

    @objc private func nextChapterButtonTapped() {
        currentChapterIndex += 1
        initialPage = 0
        loadChapter()
    }

    @objc private func pageSliderValueChanged(_ sender: UISlider) {
        let targetPage = Int(sender.value) - 1
        guard targetPage >= 0, targetPage < urls.count else { return }

        navigateToPage(targetPage)
    }

    // MARK: - Overscroll Views

    private func setupOverscrollView() {
        // Create arrow image view
        let arrowImageView = UIImageView(image: UIImage(systemName: "chevron.up"))
        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        arrowImageView.tintColor = .secondaryLabel
        arrowImageView.contentMode = .scaleAspectFit
        arrowImageView.tag = TOP_OVERSCROLL_ARROW_TAG

        // Create text label
        let textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.text = String(localized: "releaseToLoadPreviousChapter")
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.tag = TOP_OVERSCROLL_TEXT_TAG

        // Add subviews
        overscrollView.addSubview(arrowImageView)
        overscrollView.addSubview(textLabel)

        // Set up constraints
        NSLayoutConstraint.activate([
            arrowImageView.topAnchor.constraint(equalTo: overscrollView.topAnchor, constant: 8),
            arrowImageView.centerXAnchor.constraint(equalTo: overscrollView.centerXAnchor),
            arrowImageView.heightAnchor.constraint(equalToConstant: 48),
            arrowImageView.widthAnchor.constraint(equalToConstant: 48),

            textLabel.topAnchor.constraint(equalTo: arrowImageView.bottomAnchor, constant: 8),
            textLabel.leadingAnchor.constraint(equalTo: overscrollView.leadingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(
                equalTo: overscrollView.trailingAnchor, constant: -8
            ),
            textLabel.bottomAnchor.constraint(equalTo: overscrollView.bottomAnchor, constant: -8),
        ])
    }

    private func setupBottomOverscrollView() {
        // Create arrow image view (pointing down for bottom)
        let arrowImageView = UIImageView(image: UIImage(systemName: "chevron.down"))
        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        arrowImageView.tintColor = .secondaryLabel
        arrowImageView.contentMode = .scaleAspectFit
        arrowImageView.tag = BOTTOM_OVERSCROLL_ARROW_TAG

        // Create text label
        let textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.text = String(localized: "releaseToLoadNextChapter")
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.tag = BOTTOM_OVERSCROLL_TEXT_TAG

        // Add subviews
        bottomOverscrollView.addSubview(arrowImageView)
        bottomOverscrollView.addSubview(textLabel)

        // Set up constraints
        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: bottomOverscrollView.topAnchor, constant: 20),
            textLabel.leadingAnchor.constraint(
                equalTo: bottomOverscrollView.leadingAnchor, constant: 8
            ),
            textLabel.trailingAnchor.constraint(
                equalTo: bottomOverscrollView.trailingAnchor, constant: -8
            ),
            textLabel.bottomAnchor.constraint(
                equalTo: bottomOverscrollView.bottomAnchor, constant: -8
            ),

            arrowImageView.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 8),
            arrowImageView.centerXAnchor.constraint(equalTo: bottomOverscrollView.centerXAnchor),
            arrowImageView.heightAnchor.constraint(equalToConstant: 48),
            arrowImageView.widthAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func updateOverscrollViewsVisibility() {
        // Update top overscroll view
        if let arrowImageView = overscrollView.viewWithTag(TOP_OVERSCROLL_ARROW_TAG)
            as? UIImageView,
            let textLabel = overscrollView.viewWithTag(TOP_OVERSCROLL_TEXT_TAG) as? UILabel
        {
            if currentChapterIndex > 0 {
                let previousChapter = chapters[currentChapterIndex - 1]
                if previousChapter.locked == true {
                    arrowImageView.image = UIImage(systemName: "lock.fill")
                    textLabel.text = String(localized: "previousChapterIsLocked")
                } else {
                    arrowImageView.image = UIImage(systemName: "chevron.up")
                    textLabel.text = String(localized: "releaseToLoadPreviousChapter")
                }
            } else {
                arrowImageView.image = UIImage(systemName: "xmark")
                textLabel.text = String(localized: "noPreviousChapter")
            }
        }

        // Update bottom overscroll view
        if let arrowImageView = bottomOverscrollView.viewWithTag(BOTTOM_OVERSCROLL_ARROW_TAG)
            as? UIImageView,
            let textLabel = bottomOverscrollView.viewWithTag(BOTTOM_OVERSCROLL_TEXT_TAG) as? UILabel
        {
            if currentChapterIndex < chapters.count - 1 {
                let nextChapter = chapters[currentChapterIndex + 1]
                if nextChapter.locked == true {
                    arrowImageView.image = UIImage(systemName: "lock.fill")
                    textLabel.text = String(localized: "nextChapterIsLocked")
                } else {
                    arrowImageView.image = UIImage(systemName: "chevron.down")
                    textLabel.text = String(localized: "releaseToLoadNextChapter")
                }
            } else {
                arrowImageView.image = UIImage(systemName: "xmark")
                textLabel.text = String(localized: "noNextChapter")
            }
        }
    }
}

// MARK: - ContinuousReaderViewControllerWrapper

private struct ContinuousReaderViewControllerWrapper: UIViewControllerRepresentable {
    let plugin: Plugin
    let manga: DetailedManga
    let downloadManga: DetailedManga?
    let chapterGroupIndex: Int
    let chapter: Chapter
    let initialPage: Int?

    func makeUIViewController(context _: Context) -> ContinuousReaderViewController {
        return ContinuousReaderViewController(
            plugin: plugin,
            manga: manga,
            downloadManga: downloadManga,
            chapterGroupIndex: chapterGroupIndex,
            chapter: chapter,
            initialPage: initialPage
        )
    }

    func updateUIViewController(_: ContinuousReaderViewController, context _: Context) {
        // Handle any updates if needed
    }
}

// MARK: - SwiftUI Wrapper

struct ContinuousReaderScreen: View {
    let plugin: Plugin
    let manga: DetailedManga
    let downloadManga: DetailedManga?
    let chapterGroupIndex: Int
    let chapter: Chapter
    var initialPage: Int? = nil

    var body: some View {
        NavigationStack {
            ContinuousReaderViewControllerWrapper(
                plugin: plugin,
                manga: manga,
                downloadManga: downloadManga,
                chapterGroupIndex: chapterGroupIndex,
                chapter: chapter,
                initialPage: initialPage
            )
            .ignoresSafeArea()
        }
    }
}
