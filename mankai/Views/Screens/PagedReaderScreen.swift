//
//  PagedReaderScreen.swift
//  mankai
//
//  Created by Travis XU on 7/2/2026.
//

import Combine
import SwiftUI
import UIKit

// MARK: - OverscrollViewController

private enum OverscrollType {
    case previous
    case next
}

private class OverscrollViewController: UIViewController {
    let type: OverscrollType
    let orientation: NavigationOrientation
    let readingDirection: ReadingDirection
    let isLocked: Bool
    let hasChapter: Bool

    init(
        type: OverscrollType,
        orientation: NavigationOrientation,
        readingDirection: ReadingDirection,
        isLocked: Bool,
        hasChapter: Bool
    ) {
        self.type = type
        self.orientation = orientation
        self.readingDirection = readingDirection
        self.isLocked = isLocked
        self.hasChapter = hasChapter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        let arrowImageView = UIImageView()
        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        arrowImageView.tintColor = .secondaryLabel
        arrowImageView.contentMode = .scaleAspectFit

        let textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0

        containerView.addSubview(arrowImageView)
        containerView.addSubview(textLabel)

        // Position container near the edge based on navigation orientation
        var constraints: [NSLayoutConstraint] = []

        if !hasChapter || isLocked {
            // Center the container when there's no chapter or chapter is locked
            constraints.append(contentsOf: [
                containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                containerView.leadingAnchor.constraint(
                    greaterThanOrEqualTo: view.leadingAnchor, constant: 20
                ),
                containerView.trailingAnchor.constraint(
                    lessThanOrEqualTo: view.trailingAnchor, constant: -20
                ),
            ])
        } else if orientation == .vertical {
            // Position near top or bottom edge for vertical scrolling
            constraints.append(contentsOf: [
                containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                containerView.leadingAnchor.constraint(
                    greaterThanOrEqualTo: view.leadingAnchor, constant: 20
                ),
                containerView.trailingAnchor.constraint(
                    lessThanOrEqualTo: view.trailingAnchor, constant: -20
                ),
            ])

            if type == .previous {
                constraints.append(
                    containerView.bottomAnchor.constraint(
                        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40
                    )
                )
            } else {
                constraints.append(
                    containerView.topAnchor.constraint(
                        equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40
                    )
                )
            }
        } else {
            // Position near left or right edge for horizontal scrolling
            constraints.append(contentsOf: [
                containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                containerView.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            ])

            if readingDirection == .rightToLeft {
                // RTL: Previous is on right, Next is on left
                if type == .previous {
                    constraints.append(
                        containerView.leadingAnchor.constraint(
                            equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40
                        )
                    )
                } else {
                    constraints.append(
                        containerView.trailingAnchor.constraint(
                            equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40
                        )
                    )
                }
            } else {
                // LTR: Previous is on left, Next is on right
                if type == .previous {
                    constraints.append(
                        containerView.trailingAnchor.constraint(
                            equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40
                        )
                    )
                } else {
                    constraints.append(
                        containerView.leadingAnchor.constraint(
                            equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40
                        )
                    )
                }
            }
        }

        constraints.append(contentsOf: [
            arrowImageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            arrowImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            arrowImageView.heightAnchor.constraint(equalToConstant: 48),
            arrowImageView.widthAnchor.constraint(equalToConstant: 48),

            textLabel.topAnchor.constraint(equalTo: arrowImageView.bottomAnchor, constant: 16),
            textLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        NSLayoutConstraint.activate(constraints)

        configureContent(arrowImageView: arrowImageView, textLabel: textLabel)
    }

    private func configureContent(arrowImageView: UIImageView, textLabel: UILabel) {
        if !hasChapter {
            arrowImageView.image = UIImage(systemName: "xmark")
            textLabel.text =
                type == .previous
                    ? String(localized: "noPreviousChapter")
                    : String(localized: "noNextChapter")
            return
        }

        if isLocked {
            arrowImageView.image = UIImage(systemName: "lock.fill")
            textLabel.text =
                type == .previous
                    ? String(localized: "previousChapterIsLocked")
                    : String(localized: "nextChapterIsLocked")
            return
        }

        // Configure arrow direction and text
        let arrowImageName: String

        if orientation == .vertical {
            arrowImageName = type == .previous ? "chevron.up" : "chevron.down"
        } else {
            if readingDirection == .rightToLeft {
                arrowImageName = type == .previous ? "chevron.right" : "chevron.left"
            } else {
                arrowImageName = type == .previous ? "chevron.left" : "chevron.right"
            }
        }

        arrowImageView.image = UIImage(systemName: arrowImageName)
        textLabel.text =
            type == .previous
                ? String(localized: "pullToLoadPreviousChapter")
                : String(localized: "pullToLoadNextChapter")
    }
}

// MARK: - PagedReaderViewController

private class PagedReaderViewController: UIViewController, UIPageViewControllerDataSource,
    UIPageViewControllerDelegate
{
    let plugin: Plugin
    let manga: DetailedManga
    let downloadManga: DetailedManga?
    let chaptersKey: String
    let chapter: Chapter

    private var chapters: [Chapter]
    private var currentChapterIndex: Int
    private var initialPage: Int?
    private var jumpToPage: String?

    // Reader session
    private let readerSession: ReaderSession
    private var cancellables = Set<AnyCancellable>()

    /// Derived from readerSession
    private var urls: [String] {
        readerSession.urls
    }

    private var groups: [ReaderGroup] {
        readerSession.groups
    }

    // Reading state variables
    private var currentPage: Int = 0
    private var currentGroup: Int = 0

    // State variables for tab bar visibility
    var isTabBarHidden = false
    var isTabBarAnimating = false

    // State variables for navigation bar and bottom bar visibility
    var isNavigationBarHidden = false
    var isNavigationBarAnimating = false

    /// Settings (Directly from UserDefaults)
    private var respectMangaReadingDirection: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.respectMangaReadingDirection.rawValue) as? Bool
            ?? SettingsDefaults.respectMangaReadingDirection
    }

    private var readingDirection: ReadingDirection {
        if respectMangaReadingDirection, let direction = manga.readingDirection {
            return direction
        }

        return ReadingDirection(
            rawValue: UserDefaults.standard.integer(forKey: SettingsKey.PR_readingDirection.rawValue)
        )
            ?? SettingsDefaults.PR_readingDirection
    }

    private var navigationOrientation: NavigationOrientation {
        NavigationOrientation(
            rawValue: UserDefaults.standard.integer(forKey: SettingsKey.PR_navigationOrientation.rawValue)
        )
            ?? SettingsDefaults.PR_navigationOrientation
    }

    private var tapNavigation: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.PR_tapNavigation.rawValue) as? Bool
            ?? SettingsDefaults.PR_tapNavigation
    }

    private var tapNavigationBehavior: TapBehavior {
        TapBehavior(
            rawValue: UserDefaults.standard.integer(forKey: SettingsKey.PR_tapNavigationBehavior.rawValue)
        )
            ?? SettingsDefaults.PR_tapNavigationBehavior
    }

    // UI Components
    private var pageViewController: UIPageViewController!
    private let bottomBar = UIView()

    init(
        plugin: Plugin, manga: DetailedManga, downloadManga: DetailedManga?, chaptersKey: String, chapter: Chapter,
        initialPage: Int?
    ) {
        self.plugin = plugin
        self.manga = manga
        self.downloadManga = downloadManga
        self.chaptersKey = chaptersKey
        self.chapter = chapter
        self.initialPage = initialPage

        chapters = manga.chapters[chaptersKey] ?? []
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

        readerSession.readingDirection = readingDirection

        setupUI()
        setupGestures()
        setupConstraints()

        loadChapter()

        UserDefaults.standard.addObserver(
            self,
            forKeyPath: SettingsKey.PR_readingDirection.rawValue,
            options: [.new],
            context: nil
        )

        UserDefaults.standard.addObserver(
            self,
            forKeyPath: SettingsKey.respectMangaReadingDirection.rawValue,
            options: [.new],
            context: nil
        )

        UserDefaults.standard.addObserver(
            self,
            forKeyPath: SettingsKey.PR_navigationOrientation.rawValue,
            options: [.new],
            context: nil
        )

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
            self, forKeyPath: SettingsKey.PR_readingDirection.rawValue
        )
        UserDefaults.standard.removeObserver(
            self, forKeyPath: SettingsKey.respectMangaReadingDirection.rawValue
        )

        UserDefaults.standard.removeObserver(
            self, forKeyPath: SettingsKey.PR_navigationOrientation.rawValue
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

    // MARK: - Size Change

    override func viewWillTransition(
        to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.readerSession.updateGrouping()
        }
    }

    // MARK: - Observer

    override func observeValue(
        forKeyPath keyPath: String?,
        of _: Any?,
        change _: [NSKeyValueChangeKey: Any]?,
        context _: UnsafeMutableRawPointer?
    ) {
        if keyPath == SettingsKey.PR_readingDirection.rawValue
            || keyPath == SettingsKey.respectMangaReadingDirection.rawValue
        {
            readerSession.readingDirection = readingDirection
            navigateToGroup(currentGroup, animated: false)
        } else if keyPath == SettingsKey.PR_navigationOrientation.rawValue {
            // Recreate page view controller with new orientation
            recreatePageViewController()
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
        if currentGroup == lastSavedPage { return }

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
                lastSavedPage = currentGroup
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

        // Reset state
        currentGroup = 0
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
        updatePageViewController()
        updateBottomBar()
    }

    private func updatePageViewController() {
        removeLoadingAndErrorViews()

        let currentGroups = groups
        let currentUrls = urls

        guard !currentGroups.isEmpty else { return }

        if let initialPage = initialPage, initialPage >= 0, initialPage < currentUrls.count {
            let allImagesLoaded = (0 ... initialPage).allSatisfy { index in
                guard index < currentUrls.count else { return false }
                let url = currentUrls[index]
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

        // Recalculate currentGroup based on currentPage to maintain position
        if currentPage >= 0, currentPage < currentUrls.count {
            let currentUrl = currentUrls[currentPage]
            if let groupIndex = currentGroups.firstIndex(where: { $0.contains(currentUrl) }) {
                currentGroup = groupIndex
            } else {
                currentGroup = min(currentGroup, currentGroups.count - 1)
            }
        } else {
            currentGroup = min(currentGroup, currentGroups.count - 1)
        }

        // Set the initial page
        let pageVC = createPageContentViewController(for: currentGroup)
        pageViewController.setViewControllers(
            [pageVC],
            direction: .forward,
            animated: false
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
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleScreenTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        let width = view.bounds.width

        // If tap navigation is disabled, only toggle navigation bar
        if !tapNavigation {
            if isNavigationBarHidden {
                showNavigationBar()
            } else {
                hideNavigationBar()
            }
            return
        }

        // Vertical mode: use left/right taps, always previous/next behavior
        if navigationOrientation == .vertical {
            if location.x < width / 3 {
                // Left third: previous page
                navigateToGroup(currentGroup - 1, animated: true)
            } else if location.x > width * 2 / 3 {
                // Right third: next page
                navigateToGroup(currentGroup + 1, animated: true)
            } else {
                // Middle third: toggle navigation bar
                if isNavigationBarHidden {
                    showNavigationBar()
                } else {
                    hideNavigationBar()
                }
            }
            return
        }

        // Horizontal mode: left/right taps
        if location.x < width / 3 {
            // Left third: behavior depends on setting
            if tapNavigationBehavior == .previousNext {
                // Left = previous page
                navigateToGroup(currentGroup - 1, animated: true)
            } else {
                // Follow reading direction
                if readingDirection == .rightToLeft {
                    navigateToGroup(currentGroup + 1, animated: true)
                } else {
                    navigateToGroup(currentGroup - 1, animated: true)
                }
            }
        } else if location.x > width * 2 / 3 {
            // Right third: behavior depends on setting
            if tapNavigationBehavior == .previousNext {
                // Right = next page
                navigateToGroup(currentGroup + 1, animated: true)
            } else {
                // Follow reading direction
                if readingDirection == .rightToLeft {
                    navigateToGroup(currentGroup - 1, animated: true)
                } else {
                    navigateToGroup(currentGroup + 1, animated: true)
                }
            }
        } else {
            // Middle third: toggle navigation bar
            if isNavigationBarHidden {
                showNavigationBar()
            } else {
                hideNavigationBar()
            }
        }
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Create and configure page view controller
        createPageViewController()

        // Configure bottom bar
        setupBottomBar()
    }

    private func createPageViewController() {
        let orientation: UIPageViewController.NavigationOrientation =
            navigationOrientation == .vertical ? .vertical : .horizontal

        pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: orientation,
            options: nil
        )

        pageViewController.dataSource = self
        pageViewController.delegate = self

        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        pageViewController.didMove(toParent: self)
    }

    private func recreatePageViewController() {
        // Remove existing page view controller
        pageViewController.willMove(toParent: nil)
        pageViewController.view.removeFromSuperview()
        pageViewController.removeFromParent()

        // Create new page view controller with updated orientation
        createPageViewController()

        // Re-apply constraints
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Bring bottom bar to front
        view.bringSubviewToFront(bottomBar)

        // Navigate to current group
        navigateToGroup(currentGroup, animated: false)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Page view controller constraints
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Bottom bar constraints
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Loading View

    private let loaderViewTag = 1
    private let errorViewTag = 2
    private let pageInfoButtonTag = 5
    private let pageSliderTag = 6
    private let previousChapterButtonTag = 7
    private let previousButtonTag = 8
    private let nextButtonTag = 9
    private let nextChapterButtonTag = 10

    private func showLoadingView() {
        view.viewWithTag(errorViewTag)?.removeFromSuperview()
        guard view.viewWithTag(loaderViewTag) == nil else { return }

        // Create activity indicator
        let activityIndicator = UIActivityIndicatorView()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        activityIndicator.tag = loaderViewTag

        view.addSubview(activityIndicator)

        // Set up constraints
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Error View

    private func showErrorView() {
        view.viewWithTag(loaderViewTag)?.removeFromSuperview()
        guard view.viewWithTag(errorViewTag) == nil else { return }

        // Create error container
        let errorContainer = UIView()
        errorContainer.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.tag = errorViewTag

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

    private func removeLoadingAndErrorViews() {
        view.viewWithTag(loaderViewTag)?.removeFromSuperview()
        view.viewWithTag(errorViewTag)?.removeFromSuperview()
    }

    // MARK: - Page Navigation

    private func navigateToGroup(_ group: Int, animated: Bool = false) {
        let currentGroups = groups
        guard group >= 0, group < currentGroups.count else { return }

        let direction: UIPageViewController.NavigationDirection
        // Only reverse animation direction for horizontal RTL
        if navigationOrientation == .horizontal, readingDirection == .rightToLeft {
            direction = group > currentGroup ? .reverse : .forward
        } else {
            direction = group > currentGroup ? .forward : .reverse
        }

        currentGroup = group
        syncCurrentPage()

        let pageVC = createPageContentViewController(for: group)
        pageViewController.setViewControllers(
            [pageVC],
            direction: direction,
            animated: animated
        )

        updateBottomBar()
        saveRecord()
    }

    private func navigateToPage(_ page: Int, animated: Bool = false) {
        let currentUrls = urls
        let currentGroups = groups
        guard page >= 0, page < currentUrls.count else { return }

        let targetUrl = currentUrls[page]
        if let groupIndex = currentGroups.firstIndex(where: { $0.contains(targetUrl) }) {
            navigateToGroup(groupIndex, animated: animated)
        }
    }

    private func syncCurrentPage() {
        let currentUrls = urls
        let currentGroups = groups
        guard currentGroup >= 0, currentGroup < currentGroups.count else { return }

        let group = currentGroups[currentGroup]
        if let firstUrl = group.urls.first,
           let pageIndex = currentUrls.firstIndex(of: firstUrl), currentPage != pageIndex
        {
            currentPage = pageIndex
            updateBottomBar()
            saveRecord()
        }
    }

    private func createPageContentViewController(for groupIndex: Int) -> PageContentViewController {
        let currentGroups = groups
        guard groupIndex >= 0, groupIndex < currentGroups.count else {
            return PageContentViewController(
                pageIndex: 0,
                urls: [],
                images: [:],
                readingDirection: readingDirection
            )
        }

        let group = currentGroups[groupIndex]
        var groupImages: [String: ReaderImageState] = [:]
        for url in group.urls {
            groupImages[url] = readerSession.images[url]?.state ?? .loading
        }
        return PageContentViewController(
            pageIndex: groupIndex,
            urls: group.urls,
            images: groupImages,
            readingDirection: readingDirection
        )
    }

    private func createOverscrollViewController(type: OverscrollType) -> UIViewController {
        let isLocked: Bool
        let hasChapter: Bool

        if type == .previous {
            if currentChapterIndex > 0 {
                hasChapter = true
                isLocked = chapters[currentChapterIndex - 1].locked == true
            } else {
                hasChapter = false
                isLocked = false
            }
        } else {
            if currentChapterIndex < chapters.count - 1 {
                hasChapter = true
                isLocked = chapters[currentChapterIndex + 1].locked == true
            } else {
                hasChapter = false
                isLocked = false
            }
        }

        return OverscrollViewController(
            type: type,
            orientation: navigationOrientation,
            readingDirection: readingDirection,
            isLocked: isLocked,
            hasChapter: hasChapter
        )
    }

    // MARK: - UIPageViewControllerDataSource

    func pageViewController(
        _: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        if viewController is OverscrollViewController {
            return nil
        }

        guard let contentVC = viewController as? PageContentViewController else { return nil }

        let groupCount = groups.count

        let newIndex: Int
        // In vertical mode, "before" means previous page (scroll up)
        // In horizontal mode, "before" depends on reading direction
        if navigationOrientation == .vertical {
            newIndex = contentVC.pageIndex - 1
        } else if readingDirection == .rightToLeft {
            newIndex = contentVC.pageIndex + 1
        } else {
            newIndex = contentVC.pageIndex - 1
        }

        // Check if we are at the edge
        if readingDirection == .rightToLeft, navigationOrientation == .horizontal {
            // RTL Logic
            // Before -> Next Chapter (End of Chapter)
            if newIndex >= groupCount {
                return createOverscrollViewController(type: .next)
            }
            // Valid Page
            return createPageContentViewController(for: newIndex)
        } else {
            // Vertical or LTR Logic
            // Before -> Previous Chapter (Start of Chapter)
            if newIndex < 0 {
                return createOverscrollViewController(type: .previous)
            }
            // Valid Page
            return createPageContentViewController(for: newIndex)
        }
    }

    func pageViewController(
        _: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        // If current VC is OverscrollVC, we don't go further forward
        if viewController is OverscrollViewController {
            return nil
        }

        guard let contentVC = viewController as? PageContentViewController else { return nil }

        let groupCount = groups.count

        let newIndex: Int
        // In vertical mode, "after" means next page (scroll down)
        // In horizontal mode, "after" depends on reading direction
        if navigationOrientation == .vertical {
            newIndex = contentVC.pageIndex + 1
        } else if readingDirection == .rightToLeft {
            newIndex = contentVC.pageIndex - 1
        } else {
            newIndex = contentVC.pageIndex + 1
        }

        if readingDirection == .rightToLeft, navigationOrientation == .horizontal {
            // RTL Logic
            // After -> Previous Chapter (Start of Chapter)
            if newIndex < 0 {
                return createOverscrollViewController(type: .previous)
            }
            // Valid Page
            return createPageContentViewController(for: newIndex)
        } else {
            // Vertical or LTR Logic
            // After -> Next Chapter (End of Chapter)
            if newIndex >= groupCount {
                return createOverscrollViewController(type: .next)
            }
            // Valid Page
            return createPageContentViewController(for: newIndex)
        }
    }

    // MARK: - UIPageViewControllerDelegate

    func pageViewController(
        _: UIPageViewController,
        didFinishAnimating _: Bool,
        previousViewControllers _: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed else { return }

        // Check if we landed on an OverscrollViewController
        if let overscrollVC = pageViewController.viewControllers?.first as? OverscrollViewController {
            // Trigger chapter change
            if overscrollVC.type == .previous {
                if currentChapterIndex > 0 {
                    let previousChapter = chapters[currentChapterIndex - 1]
                    if previousChapter.locked != true {
                        currentChapterIndex -= 1
                        initialPage = -1
                        loadChapter()
                    }
                }
            } else {
                if currentChapterIndex < chapters.count - 1 {
                    let nextChapter = chapters[currentChapterIndex + 1]
                    if nextChapter.locked != true {
                        currentChapterIndex += 1
                        initialPage = 0
                        loadChapter()
                    }
                }
            }
            return
        }

        guard
            let currentVC = pageViewController.viewControllers?.first as? PageContentViewController
        else { return }

        currentGroup = currentVC.pageIndex
        syncCurrentPage()
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
        pageInfoButton.tag = pageInfoButtonTag

        let previousChapterButton = createBottomBarButton(systemImage: "chevron.left.to.line")
        previousChapterButton.tag = previousChapterButtonTag
        previousChapterButton.isEnabled = false

        let previousButton = createBottomBarButton(systemImage: "chevron.left")
        previousButton.tag = previousButtonTag
        previousChapterButton.isEnabled = false

        let nextButton = createBottomBarButton(systemImage: "chevron.right")
        nextButton.tag = nextButtonTag
        previousChapterButton.isEnabled = currentChapterIndex > 0

        let nextChapterButton = createBottomBarButton(systemImage: "chevron.right.to.line")
        nextChapterButton.tag = nextChapterButtonTag
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
        pageSlider.tag = pageSliderTag
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
        guard let pageInfoButton = bottomBar.viewWithTag(pageInfoButtonTag) as? UIButton,
              let previousChapterButton = bottomBar.viewWithTag(previousChapterButtonTag)
              as? UIButton,
              let previousButton = bottomBar.viewWithTag(previousButtonTag) as? UIButton,
              let nextButton = bottomBar.viewWithTag(nextButtonTag) as? UIButton,
              let nextChapterButton = bottomBar.viewWithTag(nextChapterButtonTag) as? UIButton,
              let pageSlider = bottomBar.viewWithTag(pageSliderTag) as? UISlider
        else {
            return
        }

        let totalPages = max(urls.count, 1)
        let currentGroups = groups
        pageInfoButton.setTitle("\(min(currentPage + 1, totalPages)) / \(totalPages)", for: .normal)
        previousButton.isEnabled = currentGroup != 0
        nextButton.isEnabled = currentGroup < currentGroups.count - 1

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
        navigateToGroup(currentGroup - 1, animated: true)
    }

    @objc private func pageInfoButtonTapped() {
        let chaptersModal = ChaptersModal(
            plugin: plugin,
            manga: manga,
            chaptersKey: chaptersKey
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
        navigateToGroup(currentGroup + 1, animated: true)
    }

    @objc private func nextChapterButtonTapped() {
        currentChapterIndex += 1
        initialPage = 0
        loadChapter()
    }

    @objc private func pageSliderValueChanged(sender: UISlider) {
        let targetPage = Int(sender.value) - 1
        navigateToPage(targetPage)
    }
}

// MARK: - PageContentViewController

private class PageContentViewController: UIViewController, UIScrollViewDelegate {
    let pageIndex: Int
    let urls: [String]
    let readingDirection: ReadingDirection
    var images: [String: ReaderImageState]

    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()
    private var imageViews: [String: UIImageView] = [:]
    private var imageWidthConstraints: [String: NSLayoutConstraint] = [:]
    private var loadingIndicators: [String: UIActivityIndicatorView] = [:]
    private var errorIcons: [String: UIImageView] = [:]

    init(
        pageIndex: Int, urls: [String], images: [String: ReaderImageState],
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

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Configure scroll view for zooming
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        // Configure horizontal stack view for multiple images
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

        // Create image containers for each URL
        let orderedUrls = readingDirection == .rightToLeft ? urls.reversed() : urls

        for url in orderedUrls {
            let containerView = UIView()
            containerView.translatesAutoresizingMaskIntoConstraints = false

            // Create image view
            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageViews[url] = imageView
            containerView.addSubview(imageView)

            // Create loading indicator
            let loadingIndicator = UIActivityIndicatorView(style: .large)
            loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
            loadingIndicator.hidesWhenStopped = true
            loadingIndicators[url] = loadingIndicator
            containerView.addSubview(loadingIndicator)

            // Create error icon
            let errorIcon = UIImageView()
            errorIcon.translatesAutoresizingMaskIntoConstraints = false
            errorIcon.image = UIImage(systemName: "photo.badge.exclamationmark")
            errorIcon.tintColor = .secondaryLabel
            errorIcon.contentMode = .scaleAspectFit
            errorIcon.isHidden = true
            errorIcons[url] = errorIcon
            containerView.addSubview(errorIcon)

            // Image fills the container
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

                loadingIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                loadingIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

                errorIcon.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                errorIcon.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                errorIcon.widthAnchor.constraint(equalToConstant: 48),
                errorIcon.heightAnchor.constraint(equalToConstant: 48),
            ])

            // Create width constraint based on image aspect ratio (will be updated when image loads)
            // Default to equal share of available width
            let screenWidth = UIApplication.windowBounds.width
            let defaultWidth = screenWidth / CGFloat(urls.count)
            let widthConstraint = containerView.widthAnchor.constraint(
                equalToConstant: defaultWidth
            )
            widthConstraint.isActive = true
            imageWidthConstraints[url] = widthConstraint

            contentStackView.addArrangedSubview(containerView)
        }

        // Add double tap gesture for zoom
        let doubleTapGesture = UITapGestureRecognizer(
            target: self, action: #selector(handleDoubleTap(_:))
        )
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)
    }

    private func updateContent() {
        // Calculate total aspect ratio sum of loaded images
        var aspectRatios: [String: CGFloat] = [:]
        var totalAspectRatio: CGFloat = 0

        for url in urls {
            if case let .success(actualImage) = images[url] {
                let aspectRatio = actualImage.size.width / actualImage.size.height
                aspectRatios[url] = aspectRatio
                totalAspectRatio += aspectRatio
            }
        }

        // Update width constraints based on aspect ratios
        let availableHeight = view.bounds.height
        let screenWidth = UIApplication.windowBounds.width

        for url in urls {
            guard let imageView = imageViews[url],
                  let loadingIndicator = loadingIndicators[url],
                  let errorIcon = errorIcons[url],
                  let widthConstraint = imageWidthConstraints[url]
            else { continue }

            switch images[url] ?? .loading {
            case let .success(actualImage):
                imageView.image = actualImage
                imageView.isHidden = false
                loadingIndicator.stopAnimating()
                errorIcon.isHidden = true

                // Calculate width based on image's aspect ratio to fill height
                let aspectRatio = actualImage.size.width / actualImage.size.height
                var imageWidth = availableHeight * aspectRatio

                // If total width of all images exceeds screen width, scale proportionally
                if totalAspectRatio > 0 {
                    let totalImageWidth = availableHeight * totalAspectRatio
                    if totalImageWidth > screenWidth {
                        // Scale down proportionally
                        imageWidth = (aspectRatio / totalAspectRatio) * screenWidth
                    }
                }

                widthConstraint.constant = imageWidth

            case .failed:
                imageView.isHidden = true
                loadingIndicator.stopAnimating()
                errorIcon.isHidden = false
                widthConstraint.constant = screenWidth / CGFloat(urls.count)

            case .loading:
                imageView.isHidden = true
                loadingIndicator.startAnimating()
                errorIcon.isHidden = true
            }
        }

        view.layoutIfNeeded()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let location = gesture.location(in: contentStackView)
            let zoomRect = CGRect(
                x: location.x - 50,
                y: location.y - 50,
                width: 100,
                height: 100
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in _: UIScrollView) -> UIView? {
        return contentStackView
    }
}

// MARK: - PagedReaderViewControllerWrapper

private struct PagedReaderViewControllerWrapper: UIViewControllerRepresentable {
    let plugin: Plugin
    let manga: DetailedManga
    let downloadManga: DetailedManga?
    let chaptersKey: String
    let chapter: Chapter
    let initialPage: Int?

    func makeUIViewController(context _: Context) -> PagedReaderViewController {
        return PagedReaderViewController(
            plugin: plugin,
            manga: manga,
            downloadManga: downloadManga,
            chaptersKey: chaptersKey,
            chapter: chapter,
            initialPage: initialPage
        )
    }

    func updateUIViewController(_: PagedReaderViewController, context _: Context) {
        // Handle any updates if needed
    }
}

// MARK: - SwiftUI Wrapper

struct PagedReaderScreen: View {
    let plugin: Plugin
    let manga: DetailedManga
    let downloadManga: DetailedManga?
    let chaptersKey: String
    let chapter: Chapter
    var initialPage: Int? = nil

    var body: some View {
        NavigationStack {
            PagedReaderViewControllerWrapper(
                plugin: plugin,
                manga: manga,
                downloadManga: downloadManga,
                chaptersKey: chaptersKey,
                chapter: chapter,
                initialPage: initialPage
            )
            .ignoresSafeArea()
        }
    }
}
