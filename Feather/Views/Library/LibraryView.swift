//
//  ContentView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import CoreData
import NimbleViews

// MARK: - View
struct LibraryView: View {
	enum Mode: Equatable {
		case imported
		case signed
		
		var title: String {
			switch self {
			case .imported: return .localized("Imported")
			case .signed: return .localized("Signed")
			}
		}
	}
	
	let mode: Mode
	
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject var updateManager = UpdateManager.shared
	@AppStorage("Feather.showURLImportButton") private var _showURLImportButton = false
	
	@State private var _selectedInfoAppPresenting: AnyApp?
	@State private var _selectedSigningAppPresenting: AnyApp?
	@State private var _selectedInstallAppPresenting: AnyApp?
	@State private var _isImportingPresenting = false
	@State private var _isDownloadingPresenting = false
	@State private var _alertDownloadString: String = ""
	@State private var _updateCheckRotation = 0.0
	@State private var _isUpdateCheckCompleteVisible = false
	
	// MARK: Selection State
	@State private var _selectedAppUUIDs: Set<String> = []
	@State private var _editMode: EditMode = .inactive
	
	@State private var _searchText = ""
	
	@Namespace private var _namespace
	
	private func filteredAndSortedApps<T>(from apps: FetchedResults<T>) -> [T] where T: NSManagedObject {
		apps.filter {
			_searchText.isEmpty ||
				(($0.value(forKey: "name") as? String)?.localizedCaseInsensitiveContains(_searchText) ?? false)
		}
	}
	
	private var _filteredSignedApps: [Signed] {
		filteredAndSortedApps(from: _signedApps)
	}
	
	private var _filteredImportedApps: [Imported] {
		filteredAndSortedApps(from: _importedApps)
	}
	
	private var _currentListIsEmpty: Bool {
		switch mode {
		case .imported:
			return _filteredImportedApps.isEmpty
		case .signed:
			return _filteredSignedApps.isEmpty
		}
	}
	
	// MARK: Fetch
	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
		animation: .snappy
	) private var _signedApps: FetchedResults<Signed>
	
	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _importedApps: FetchedResults<Imported>
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>
	
	// MARK: Body
	var body: some View {
		NBNavigationView(mode.title) {
			NBListAdaptable {
				switch mode {
				case .imported:
					ForEach(_filteredImportedApps, id: \.uuid) { app in
						LibraryCellView(
							app: app,
							selectedInfoAppPresenting: $_selectedInfoAppPresenting,
							selectedSigningAppPresenting: $_selectedSigningAppPresenting,
							selectedInstallAppPresenting: $_selectedInstallAppPresenting,
							selectedAppUUIDs: $_selectedAppUUIDs
						)
						.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
					}
				case .signed:
					ForEach(_filteredSignedApps, id: \.uuid) { app in
						LibraryCellView(
							app: app,
							selectedInfoAppPresenting: $_selectedInfoAppPresenting,
							selectedSigningAppPresenting: $_selectedSigningAppPresenting,
							selectedInstallAppPresenting: $_selectedInstallAppPresenting,
							selectedAppUUIDs: $_selectedAppUUIDs
						)
						.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
					}
				}
			}
			.searchable(text: $_searchText, placement: .platform())
			.scrollDismissesKeyboard(.interactively)
			.overlay {
				if _currentListIsEmpty {
					if #available(iOS 17, *) {
						ContentUnavailableView {
							Label(
								mode == .imported ? .localized("No Imported Apps") : .localized("No Signed Apps"),
								systemImage: mode == .imported ? "tray.and.arrow.down" : "checkmark.seal"
							)
						} description: {
							Text(
								mode == .imported
									? .localized("Get started by importing your first IPA file.")
									: .localized("Signed apps will appear here after signing.")
							)
						} actions: {
							if mode == .imported {
								Button {
									_isImportingPresenting = true
								} label: {
									NBButton(.localized("Import from Files"), style: .text)
								}
							}
						}
					}
				}
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					EditButton()
				}
				
				if _editMode.isEditing {
					NBToolbarButton(
						.localized("Delete"),
						systemImage: "trash",
						isDisabled: _selectedAppUUIDs.isEmpty
					) {
						_bulkDeleteSelectedApps()
					}
				} else {
					if mode == .signed {
						ToolbarItem(placement: .topBarTrailing) {
							Button {
								Task {
									await _checkForUpdates()
								}
							} label: {
								Image(systemName: _isUpdateCheckCompleteVisible ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
									.rotationEffect(.degrees(_updateCheckRotation))
									.animation(
										updateManager.isChecking
											? .linear(duration: 0.8).repeatForever(autoreverses: false)
											: .default,
										value: _updateCheckRotation
									)
							}
							.disabled(updateManager.isChecking)
							.accessibilityLabel(.localized("Check for Updates"))
						}
					}
					
					if mode == .imported {
						if _showURLImportButton {
							ToolbarItem(placement: .topBarTrailing) {
								Button {
									_isDownloadingPresenting = true
								} label: {
									Image(systemName: "link")
								}
								.accessibilityLabel(.localized("Import from URL"))
							}
						}
						
						ToolbarItem(placement: .topBarTrailing) {
							Menu {
								_importActions()
							} label: {
								Image(systemName: "plus")
							} primaryAction: {
								_isImportingPresenting = true
							}
							.accessibilityLabel(.localized("Import from Files"))
						}
					}
				}
			}
			.environment(\.editMode, $_editMode)
			.sheet(item: $_selectedInfoAppPresenting) { app in
				LibraryInfoView(app: app.base)
			}
			.sheet(item: $_selectedInstallAppPresenting) { app in
				InstallPreviewView(app: app.base, isSharing: app.archive)
					.presentationDetents([.height(200)])
					.presentationDragIndicator(.visible)
			}
			.fullScreenCover(item: $_selectedSigningAppPresenting) { app in
				SigningView(app: app.base)
					.compatNavigationTransition(id: app.base.uuid ?? "", ns: _namespace)
			}
			.sheet(isPresented: $_isImportingPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes: [.ipa, .tipa],
					allowsMultipleSelection: true,
					onDocumentsPicked: { urls in
						guard !urls.isEmpty else { return }
						
						for url in urls {
							let id = "FeatherManualDownload_\(UUID().uuidString)"
							let dl = downloadManager.startArchive(from: url, id: id)
							try? downloadManager.handlePachageFile(url: url, dl: dl)
						}
					}
				)
				.ignoresSafeArea()
			}
			.alert(.localized("Import from URL"), isPresented: $_isDownloadingPresenting) {
				TextField(.localized("URL"), text: $_alertDownloadString)
					.textInputAutocapitalization(.never)
				Button(.localized("Cancel"), role: .cancel) {
					_alertDownloadString = ""
				}
				Button(.localized("OK")) {
					_startURLImport(_alertDownloadString)
				}
			}
			.onReceive(NotificationCenter.default.publisher(for: Notification.Name("Feather.installApp"))) { _ in
				if let latest = _signedApps.first {
					_selectedInstallAppPresenting = AnyApp(base: latest)
				}
			}
			.onChange(of: _editMode) { mode in
				if mode == .inactive {
					_selectedAppUUIDs.removeAll()
				}
			}
			.onChange(of: updateManager.isChecking) { isChecking in
				_handleUpdateCheckStateChange(isChecking)
			}
		}
	}
}

// MARK: - Extension: Import
extension LibraryView {
	@ViewBuilder
	private func _importActions() -> some View {
		Button(.localized("Import from Files"), systemImage: "folder") {
			_isImportingPresenting = true
		}
		Button(.localized("Import from URL"), systemImage: "globe") {
			_isDownloadingPresenting = true
		}
		Button(.localized("Paste URL"), systemImage: "doc.on.clipboard") {
			_importFromClipboard()
		}
	}
	
	private func _importFromClipboard() {
		guard let value = UIPasteboard.general.string else { return }
		_startURLImport(value)
	}
	
	private func _startURLImport(_ value: String) {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return }
		_ = downloadManager.startDownload(
			from: url,
			id: "FeatherManualDownload_\(UUID().uuidString)"
		)
		_alertDownloadString = ""
	}
}

// MARK: - Extension: Bulk Delete
extension LibraryView {
	private func _bulkDeleteSelectedApps() {
		let selectedApps = _getCurrentApps().filter { app in
			guard let uuid = app.uuid else { return false }
			return _selectedAppUUIDs.contains(uuid)
		}
		
		for app in selectedApps {
			Storage.shared.deleteApp(for: app)
		}
		
		_selectedAppUUIDs.removeAll()
	}
	
	private func _getCurrentApps() -> [AppInfoPresentable] {
		switch mode {
		case .imported:
			return _filteredImportedApps.map { $0 as AppInfoPresentable }
		case .signed:
			return _filteredSignedApps.map { $0 as AppInfoPresentable }
		}
	}
	
	private func _checkForUpdates() async {
		let localApps = _signedApps.map { $0 as AppInfoPresentable } + _importedApps.map { $0 as AppInfoPresentable }
		await updateManager.checkForUpdates(
			sources: Array(_sources),
			localApps: localApps
		)
	}
	
	private func _handleUpdateCheckStateChange(_ isChecking: Bool) {
		if isChecking {
			_isUpdateCheckCompleteVisible = false
			_updateCheckRotation = 0
			withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
				_updateCheckRotation = 360
			}
		} else {
			withAnimation(.none) {
				_updateCheckRotation = 0
			}
			
			_isUpdateCheckCompleteVisible = true
			Task { @MainActor in
				try? await Task.sleep(nanoseconds: 900_000_000)
				if !updateManager.isChecking {
					_isUpdateCheckCompleteVisible = false
				}
			}
		}
	}
}
