//
//  TabEnum.swift
//  feather
//
//  Created by samara on 22.03.2025.
//

import SwiftUI
import NimbleViews

enum TabEnum: String, CaseIterable, Hashable {
	case imported
	case signed
	case sources
	case settings
	case certificates
	
	var title: String {
		switch self {
		case .imported: 	return .localized("Imported")
		case .signed: 		return .localized("Signed")
		case .sources: 		return .localized("Sources")
		case .settings: 	return .localized("Settings")
		case .certificates:	return .localized("Certificates")
		}
	}
	
	var icon: String {
		switch self {
		case .imported: 	return "tray.and.arrow.down"
		case .signed: 		return "checkmark.seal"
		case .sources: 		return "globe.desk"
		case .settings: 	return "gearshape.2"
		case .certificates: return "person.text.rectangle"
		}
	}
	
	@ViewBuilder
	static func view(for tab: TabEnum) -> some View {
		switch tab {
		case .imported: ImportedView()
		case .signed: SignedView()
		case .sources: SourcesView()
		case .settings: SettingsView()
		case .certificates: NBNavigationView(.localized("Certificates")) { CertificatesView() }
		}
	}
	
	static var defaultTabs: [TabEnum] {
		return [
			.imported,
			.signed,
			.sources,
			.settings
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return [
			.certificates
		]
	}
}
