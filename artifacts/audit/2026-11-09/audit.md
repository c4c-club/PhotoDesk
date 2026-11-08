# M15 Audit Report

- stamp: 2026-11-09 00:33:33+08:00
- mode: BASELINE (P0 gates informational)

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
- viewForZooming = 6
- UIScrollViewDelegate = 1
- setZoomScale = 7
- contentInset = 5
- zoomContentView = 27
- zoomScale_info_count = 14
- scrollViewDidZoom = 5

## P0-2 position
- positionStore_save_calls = 2
- userdefaults_position_writes = 3
- beginRestore_calls = 2
- viewWillDisappear_conditional = 0
- machine_maxAttempts = 0
- machine_timeout_3s = 0
- position_file_store = False
- restore_machine_v5 = False

## P0-3/4 marquee
- slideSelectRangePolicy_refs = 14
- insert_only_target_baseIDs = 2
- whole_row_banner = 0
- marquee_policy = False
- range_policy_file = True
- range_policy_tests = True
- old_tests_still_present = 2

## Tests (func test count)
- PhotoDeskTests = 191
- PhotoDeskUITests = 57
- PhotoDeskCore/Tests = 270

## Pages (29 view/viewcontroller files)
- PhotoDesk/Features/Albums/AlbumDetailView.swift (123 lines, ax=False)
- PhotoDesk/Features/Albums/AlbumsView.swift (151 lines, ax=False)
- PhotoDesk/Features/Cleanup/CleanupView.swift (293 lines, ax=True)
- PhotoDesk/Features/Editor/CropOverlayView.swift (134 lines, ax=False)
- PhotoDesk/Features/Editor/EditorViewController.swift (277 lines, ax=False)
- PhotoDesk/Features/Export/ExportView.swift (157 lines, ax=True)
- PhotoDesk/Features/Export/StorageStatsView.swift (299 lines, ax=True)
- PhotoDesk/Features/Library/LibraryViewController.swift (1519 lines, ax=True)
- PhotoDesk/Features/Library/LocationFilterView.swift (129 lines, ax=False)
- PhotoDesk/Features/Library/RecentlyDeletedView.swift (52 lines, ax=False)
- PhotoDesk/Features/Metadata/MetadataView.swift (214 lines, ax=True)
- PhotoDesk/Features/Onboarding/GestureTutorialView.swift (73 lines, ax=False)
- PhotoDesk/Features/Onboarding/PermissionIntroView.swift (67 lines, ax=False)
- PhotoDesk/Features/Search/SearchView.swift (262 lines, ax=True)
- PhotoDesk/Features/Session/SessionBadgeView.swift (35 lines, ax=True)
- PhotoDesk/Features/Session/SessionReviewView.swift (204 lines, ax=True)
- PhotoDesk/Features/Settings/ActionPickerView.swift (68 lines, ax=False)
- PhotoDesk/Features/Settings/AppearanceSettingsView.swift (68 lines, ax=True)
- PhotoDesk/Features/Settings/CacheManagerView.swift (101 lines, ax=True)
- PhotoDesk/Features/Settings/DiagnosticsView.swift (70 lines, ax=False)
- PhotoDesk/Features/Settings/GestureSettingsView.swift (105 lines, ax=True)
- PhotoDesk/Features/Settings/PrivacyView.swift (54 lines, ax=False)
- PhotoDesk/Features/Settings/SecuritySettingsView.swift (80 lines, ax=True)
- PhotoDesk/Features/Settings/SettingsView.swift (84 lines, ax=True)
- PhotoDesk/Features/Vault/VaultGridView.swift (123 lines, ax=False)
- PhotoDesk/Features/Vault/VaultView.swift (225 lines, ax=True)
- PhotoDesk/Features/Viewer/ActionOverlayView.swift (105 lines, ax=False)
- PhotoDesk/Features/Viewer/FilmStripView.swift (138 lines, ax=False)
- PhotoDesk/Features/Viewer/ViewerViewController.swift (1024 lines, ax=True)

## RESULT: PASS
