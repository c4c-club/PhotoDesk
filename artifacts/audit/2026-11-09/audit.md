# M15 Audit Report

- stamp: 2026-11-12 03:02:22+08:00
- mode: GATE (P0 must be 0)

## Red lines (must be 0)
- urlsession = 0
- core_apple_imports = 0
- force_try = 0
- force_cast = 0
- ios17_observable = 0
- contentUnavailableView = 0
- swiftData = 0
- scrollTargetBehavior = 0
- scrollPosition = 0
- permanent_delete_entry = 0

## P0-1 zoom symbols in Viewer
- viewForZooming = 0
- UIScrollViewDelegate = 0
- setZoomScale = 0
- contentInset = 0
- zoomContentView = 0
- zoomScale_info_count = 9
- scrollViewDidZoom = 0

## P0-2 position
- positionStore_save_calls = 2
- userdefaults_position_writes = 2
- beginRestore_calls = 2
- viewWillDisappear_conditional = 1
- machine_maxAttempts = 0
- machine_timeout_3s = 0
- position_file_store = True
- restore_machine_v5 = True

## P0-3/4 marquee
- slideSelectRangePolicy_refs = 0
- insert_only_target_baseIDs = 0
- whole_row_banner = 0
- marquee_policy = True
- range_policy_file = False
- range_policy_tests = False
- old_tests_still_present = 0

## Tests (func test count)
- PhotoDeskTests = 223
- PhotoDeskUITests = 67
- PhotoDeskCore/Tests = 338

## Pages (29 view/viewcontroller files)
- PhotoDesk/Features/Albums/AlbumDetailView.swift (151 lines, ax=False)
- PhotoDesk/Features/Albums/AlbumsView.swift (189 lines, ax=False)
- PhotoDesk/Features/Cleanup/CleanupView.swift (308 lines, ax=True)
- PhotoDesk/Features/Editor/CropOverlayView.swift (134 lines, ax=False)
- PhotoDesk/Features/Editor/EditorViewController.swift (294 lines, ax=False)
- PhotoDesk/Features/Export/ExportView.swift (162 lines, ax=True)
- PhotoDesk/Features/Export/StorageStatsView.swift (299 lines, ax=True)
- PhotoDesk/Features/Library/LibraryViewController.swift (1745 lines, ax=True)
- PhotoDesk/Features/Library/LocationFilterView.swift (129 lines, ax=False)
- PhotoDesk/Features/Library/RecentlyDeletedView.swift (83 lines, ax=False)
- PhotoDesk/Features/Metadata/MetadataView.swift (237 lines, ax=True)
- PhotoDesk/Features/Onboarding/GestureTutorialView.swift (131 lines, ax=True)
- PhotoDesk/Features/Onboarding/PermissionIntroView.swift (84 lines, ax=True)
- PhotoDesk/Features/Search/SearchView.swift (272 lines, ax=True)
- PhotoDesk/Features/Session/SessionBadgeView.swift (35 lines, ax=True)
- PhotoDesk/Features/Session/SessionReviewView.swift (225 lines, ax=True)
- PhotoDesk/Features/Settings/ActionPickerView.swift (68 lines, ax=False)
- PhotoDesk/Features/Settings/AppearanceSettingsView.swift (94 lines, ax=True)
- PhotoDesk/Features/Settings/CacheManagerView.swift (101 lines, ax=True)
- PhotoDesk/Features/Settings/DiagnosticsView.swift (105 lines, ax=True)
- PhotoDesk/Features/Settings/GestureSettingsView.swift (131 lines, ax=True)
- PhotoDesk/Features/Settings/PrivacyView.swift (88 lines, ax=True)
- PhotoDesk/Features/Settings/SecuritySettingsView.swift (80 lines, ax=True)
- PhotoDesk/Features/Settings/SettingsView.swift (92 lines, ax=True)
- PhotoDesk/Features/Vault/VaultGridView.swift (123 lines, ax=False)
- PhotoDesk/Features/Vault/VaultView.swift (241 lines, ax=True)
- PhotoDesk/Features/Viewer/ActionOverlayView.swift (105 lines, ax=False)
- PhotoDesk/Features/Viewer/FilmStripView.swift (138 lines, ax=False)
- PhotoDesk/Features/Viewer/ViewerViewController.swift (1117 lines, ax=True)

## RESULT: PASS
