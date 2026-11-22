import AppKit
import SwiftUI

struct AppUpdateFooter: View {
    private enum Status {
        case checking, current, checkFailed
        case available(AppUpdateRelease, downloadFailed: Bool)
        case downloading(AppUpdateRelease, AppUpdateRelease.DiskImage)
        case ready(AppUpdateRelease, URL, openFailed: Bool)

        var release: AppUpdateRelease? {
            switch self {
            case .available(let release, _), .downloading(let release, _), .ready(let release, _, _): release
            default: nil
            }
        }

        var work: Work? {
            switch self {
            case .checking: .check
            case .downloading(let release, let image): .download(release, image)
            default: nil
            }
        }
    }

    private enum Work: Equatable {
        case check
        case download(AppUpdateRelease, AppUpdateRelease.DiskImage)
    }

    private static let installed = RunningAppVersion.current()
    private var installed: RunningAppVersion { Self.installed }
    @State private var status: Status = .checking
    @State private var isPresented = false

    var body: some View {
        let work = status.work
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: AirTranslateDesign.Spacing.xs) {
                Text(installed.version.map { "v\($0)" } ?? AppUpdateCopy.unknownVersion)
                    .monospacedDigit()
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                if let release = status.release {
                    Label(AppUpdateCopy.available(release.version), systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(AirTranslateDesign.Palette.accent)
                }
            }
            .font(AirTranslateDesign.Typography.meta)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .help(AppUpdateCopy.softwareUpdate)
        .accessibilityLabel(AppUpdateCopy.softwareUpdate)
        .accessibilityValue([installed.summary, status.release.map { AppUpdateCopy.available($0.version) }]
            .compactMap { $0 }.joined(separator: ", "))
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            updatePanel
        }
        .task(id: work) {
            if let work { await perform(work) }
        }
    }

    private var updatePanel: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.sm) {
            Text(AppUpdateCopy.softwareUpdate).font(.headline)
            if let installedVersion = installed.summary {
                Text(AppUpdateCopy.installed(installedVersion)).foregroundStyle(.secondary)
            }

            switch status {
            case .checking:
                progress(AppUpdateCopy.checking)
            case .current:
                Text(AppUpdateCopy.current)
                checkButton
            case .checkFailed:
                Text(AppUpdateCopy.checkFailed)
                checkButton
                Link(AppUpdateCopy.releaseNotes, destination: AppUpdateService.releasesURL)
            case .available(let release, let downloadFailed):
                Text(AppUpdateCopy.available(release.version)).fontWeight(.semibold)
                if downloadFailed { Text(AppUpdateCopy.downloadFailed) }
                if let image = release.diskImage {
                    Button(downloadFailed ? AppText.retry : AppUpdateCopy.download) {
                        status = .downloading(release, image)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text(AppUpdateCopy.manualDownload)
                }
                Link(AppUpdateCopy.releaseNotes, destination: release.notesURL)
            case .downloading(let release, _):
                progress(AppUpdateCopy.downloading)
                Button(AppUpdateCopy.cancel) { status = .available(release, downloadFailed: false) }
            case .ready(let release, let file, let openFailed):
                Text(openFailed ? AppUpdateCopy.openFailed : AppUpdateCopy.installInstructions)
                Button(AppUpdateCopy.openInstaller) {
                    if !NSWorkspace.shared.open(file) {
                        status = .ready(release, file, openFailed: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                Link(AppUpdateCopy.releaseNotes, destination: release.notesURL)
            }
        }
        .padding(AirTranslateDesign.Spacing.md)
        .frame(width: 300, alignment: .leading)
    }

    private var checkButton: some View {
        Button(AppUpdateCopy.check) { status = .checking }
    }

    private func progress(_ label: String) -> some View {
        ProgressView { Text(label) }.controlSize(.small)
    }

    private func perform(_ work: Work) async {
        switch work {
        case .check:
            do {
                let release = try await AppUpdateService.check(installedVersion: installed.version)
                guard !Task.isCancelled, status.work == work else { return }
                status = release.map { .available($0, downloadFailed: false) } ?? .current
            } catch {
                guard !Task.isCancelled, status.work == work else { return }
                status = .checkFailed
            }
        case .download(let release, let image):
            do {
                let file = try await AppUpdateService.download(image)
                guard !Task.isCancelled, status.work == work else {
                    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
                    return
                }
                status = .ready(release, file, openFailed: false)
            } catch {
                guard !Task.isCancelled, status.work == work else { return }
                status = .available(release, downloadFailed: true)
            }
        }
    }
}

private enum AppUpdateCopy {
    static let softwareUpdate = AppText.localized(
        english: "Software Update", korean: "소프트웨어 업데이트", japanese: "ソフトウェアアップデート", chineseSimplified: "软件更新"
    )
    static let unknownVersion = AppText.localized(
        english: "Version unknown", korean: "버전 정보 없음", japanese: "バージョン不明", chineseSimplified: "版本未知"
    )
    static let check = AppText.localized(
        english: "Check for Updates", korean: "업데이트 확인", japanese: "アップデートを確認", chineseSimplified: "检查更新"
    )
    static let checking = AppText.localized(
        english: "Checking for updates…", korean: "업데이트 확인 중…", japanese: "アップデートを確認中…", chineseSimplified: "正在检查更新…"
    )
    static let current = AppText.localized(
        english: "AirTranslate is up to date.", korean: "최신 버전을 사용 중입니다.",
        japanese: "AirTranslate は最新です。", chineseSimplified: "AirTranslate 已是最新版本。"
    )
    static let checkFailed = AppText.localized(
        english: "Couldn’t check for updates. Try again or visit GitHub.", korean: "업데이트를 확인하지 못했습니다. 다시 시도하거나 GitHub에서 확인하세요.",
        japanese: "アップデートを確認できませんでした。もう一度試すか、GitHub をご覧ください。", chineseSimplified: "无法检查更新。请重试或前往 GitHub 查看。"
    )
    static let download = AppText.localized(
        english: "Download Update", korean: "업데이트 다운로드", japanese: "アップデートをダウンロード", chineseSimplified: "下载更新"
    )
    static let downloading = AppText.localized(
        english: "Downloading and verifying…", korean: "다운로드 및 검증 중…", japanese: "ダウンロードと検証中…", chineseSimplified: "正在下载和验证…"
    )
    static let downloadFailed = AppText.localized(
        english: "Couldn’t download or verify the installer.", korean: "설치 파일을 다운로드하거나 검증하지 못했습니다.",
        japanese: "インストーラーのダウンロードまたは検証に失敗しました。", chineseSimplified: "无法下载或验证安装文件。"
    )
    static let manualDownload = AppText.localized(
        english: "See the release notes for installation options.", korean: "설치 방법은 릴리즈 노트에서 확인하세요.",
        japanese: "インストール方法はリリースノートをご覧ください。", chineseSimplified: "请查看发布说明了解安装方式。"
    )
    static let openInstaller = AppText.localized(
        english: "Open Installer", korean: "설치 파일 열기", japanese: "インストーラーを開く", chineseSimplified: "打开安装文件"
    )
    static let openFailed = AppText.localized(
        english: "Couldn’t open the installer. You can also download it from the release notes.",
        korean: "설치 파일을 열지 못했습니다. 릴리즈 노트에서도 다운로드할 수 있습니다.",
        japanese: "インストーラーを開けませんでした。リリースノートからもダウンロードできます。", chineseSimplified: "无法打开安装文件。也可以从发布说明下载。"
    )
    static let installInstructions = AppText.localized(
        english: "The download is verified. Open the installer, quit AirTranslate, then drag the new app into Applications.",
        korean: "다운로드를 검증했습니다. 설치 파일을 열고 AirTranslate를 종료한 다음 새 앱을 응용 프로그램 폴더로 옮기세요.",
        japanese: "ダウンロードを検証しました。インストーラーを開き、AirTranslate を終了して、新しいアプリを「アプリケーション」に移動してください。",
        chineseSimplified: "下载已验证。打开安装文件，退出 AirTranslate，然后将新版应用拖入「应用程序」文件夹。"
    )
    static let releaseNotes = AppText.localized(
        english: "Release Notes", korean: "릴리즈 노트", japanese: "リリースノート", chineseSimplified: "发布说明"
    )
    static let cancel = AppText.localized(
        english: "Cancel", korean: "취소", japanese: "キャンセル", chineseSimplified: "取消"
    )

    static func installed(_ version: String) -> String {
        AppText.localized(
            english: "Installed version \(version)", korean: "현재 버전 \(version)",
            japanese: "現在のバージョン \(version)", chineseSimplified: "当前版本 \(version)"
        )
    }

    static func available(_ version: String) -> String {
        AppText.localized(
            english: "Update \(version) available", korean: "\(version) 업데이트 가능",
            japanese: "\(version) にアップデート可能", chineseSimplified: "可更新至 \(version)"
        )
    }
}
