// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settings => 'Settings';

  @override
  String get exceptions => 'Exceptions';

  @override
  String get permissions => 'Access';

  @override
  String get appearance => 'Appearance';

  @override
  String get rules => 'Rules';

  @override
  String get statistics => 'Statistics';

  @override
  String get account => 'License';

  @override
  String get about => 'About';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get unavailable => 'Native runtime unavailable';

  @override
  String get errorUnavailable => 'This operation is unavailable.';

  @override
  String get errorPermission => 'Permission denied. Review access permissions.';

  @override
  String get errorConflict =>
      'Settings changed elsewhere. Review and try again.';

  @override
  String get errorInvalid => 'Invalid value. Review your entry.';

  @override
  String get errorDuplicate => 'This word already exists.';

  @override
  String get errorIO =>
      'Unable to save. Your confirmed settings were preserved.';

  @override
  String get errorTimeout => 'No response. Reconnect before trying again.';

  @override
  String get autoEnabled => 'Automatic layout correction';

  @override
  String get typoEnabled => 'Common typos and double capitals';

  @override
  String get yoEnabled => 'Restore the letter ё';

  @override
  String get singleShiftEnabled => 'Single Shift switches layout';

  @override
  String get optionEnabled => 'Option triggers manual correction';

  @override
  String get splitShiftEnabled => 'Left + right Shift toggles automation';

  @override
  String get plainPasteEnabled => '⌘ ⇧ V pastes plain text';

  @override
  String get soundEnabled => 'Play correction sound';

  @override
  String get settingsIntro =>
      'Your keyboard, your way. Changes are saved on this Mac.';

  @override
  String get manualHint =>
      'Double Shift switches the last word back and forth, or converts selected text. Other Shift combinations work as usual.';

  @override
  String get words => 'Words';

  @override
  String get applications => 'Applications';

  @override
  String get addWord => 'Add word';

  @override
  String get wordHint => '1–20 characters; saved locally';

  @override
  String get clearWords => 'Clear words';

  @override
  String get clearQuestion =>
      'Clear every word exception? This cannot be undone.';

  @override
  String get emptyWords => 'No word exceptions yet.';

  @override
  String get legacy => 'Imported legacy exception — original preserved';

  @override
  String get chooseApp => 'Choose .app…';

  @override
  String get appHint =>
      'Choose which apps can use automatic correction. Manual shortcuts stay available.';

  @override
  String get allow => 'Allow automation';

  @override
  String get deny => 'Disable automation';

  @override
  String get emptyApps => 'No application rules yet.';

  @override
  String get edit => 'Edit';

  @override
  String get accessIntro =>
      'Allow each capability explicitly. Secure Input is respected and cannot be disabled here.';

  @override
  String get listen => 'Listen to keyboard events';

  @override
  String get post => 'Post replacement events';

  @override
  String get ax => 'Accessibility trust';

  @override
  String get granted => 'Granted';

  @override
  String get notGranted => 'Not granted';

  @override
  String get request => 'Request access';

  @override
  String get permissionCheckMissing =>
      'Checked. macOS has not yet granted access to this copy of Necaramba. If the switches are already on, remove the old Necaramba entry from the relevant list and add the current copy using “+”, then restart the app.';

  @override
  String get refresh => 'Refresh status';

  @override
  String get secureInput => 'Secure Input';

  @override
  String get active => 'Active';

  @override
  String get inactive => 'Inactive';

  @override
  String get color => 'Header color';

  @override
  String get resetColor => 'Reset color';

  @override
  String get headerImage => 'Header image';

  @override
  String get dropHint => 'Drop an image onto the top bar to personalize it.';

  @override
  String get removeImage => 'Remove image';

  @override
  String get previewImage => 'Refresh image preview';

  @override
  String get sound => 'Correction sound';

  @override
  String get customSound => 'Custom sound';

  @override
  String get defaultSound => 'Default sound';

  @override
  String get chooseSound => 'Choose sound…';

  @override
  String get resetSound => 'Reset sound';

  @override
  String get rulesIntro =>
      'Updates use independently signed rules. Offline operation keeps the installed rules.';

  @override
  String get version => 'Version';

  @override
  String get lastChecked => 'Last checked';

  @override
  String get never => 'Never';

  @override
  String get checkRules => 'Check for updates';

  @override
  String get share => 'Suggest a rule';

  @override
  String get shareIntro =>
      'Nothing is sent until you review the exact preview and confirm.';

  @override
  String get word => 'Word';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get russian => 'Russian';

  @override
  String get feedback => 'Feedback (optional)';

  @override
  String get previewSubmission => 'Preview submission';

  @override
  String get sharePreview => 'Review submission';

  @override
  String get destination => 'Destination host';

  @override
  String get modelVersion => 'Rule model version';

  @override
  String get send => 'Send this rule';

  @override
  String get statisticsIntro =>
      'Only aggregate counts are stored. No typed text is collected.';

  @override
  String get estimate => 'Estimated time saved';

  @override
  String get formula =>
      'Estimate v1: layout/manual × 1 s; typo/double capitals/ё × 2 s; undo × 0 s.';

  @override
  String get seconds => 'seconds';

  @override
  String get resetCounters => 'Reset counters';

  @override
  String get resetQuestion => 'Reset aggregate statistics?';

  @override
  String get layout => 'Layout';

  @override
  String get typo => 'Typos';

  @override
  String get doubleCaps => 'Double capitals';

  @override
  String get yo => 'Letter ё';

  @override
  String get manual => 'Manual corrections';

  @override
  String get undo => 'Undo';

  @override
  String get licenseIntro =>
      'Manage your license and purchases through the App Store.';

  @override
  String get purchase => 'Purchase';

  @override
  String get restore => 'Restore purchases';

  @override
  String get manageSubscription => 'Manage subscription';

  @override
  String get expires => 'Expires';

  @override
  String get trial => 'Trial';

  @override
  String get expired => 'Expired';

  @override
  String get licensed => 'Licensed';

  @override
  String get blocked => 'Blocked';

  @override
  String get unknown => 'Unknown';

  @override
  String get aboutIntro =>
      'Keyboard correction for Russian and English.\nWorks locally on your Mac.\nmacOS 12 and later';

  @override
  String get login => 'Launch at login';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get privacy =>
      'Exports contain aggregate counters and system metadata, never keyboard input. Archives contain your explicitly saved rules and settings.';

  @override
  String get exportDiagnostics => 'Export diagnostics…';

  @override
  String get exportArchive => 'Export settings and rules…';

  @override
  String get importArchive => 'Import settings and rules…';

  @override
  String get importQuestion =>
      'Import a validated archive? Conflicting or invalid archives are rejected without changing existing data.';

  @override
  String get localOnly => 'On this Mac';

  @override
  String get status => 'Runtime status';

  @override
  String get working => 'Waiting for native confirmation…';

  @override
  String get permissionRequired => 'Permission required';

  @override
  String get off => 'Automation off';

  @override
  String get licensingBlocked => 'License required';

  @override
  String get updateAvailable => 'Update available';

  @override
  String get current => 'Up to date';

  @override
  String get offline => 'Offline';

  @override
  String get checking => 'Checking';

  @override
  String get failed => 'Check failed';

  @override
  String get enabled => 'Enabled';

  @override
  String get disabled => 'Disabled';

  @override
  String get requiresApproval => 'Requires approval in System Settings';

  @override
  String get help => 'Help & privacy';

  @override
  String get helpText =>
      'Use Shift shortcuts for manual correction. Automatic correction requires listen and post access. Exceptions remain on this Mac. Network operations require explicit action or configured rule updates. Support and purchase services may be unavailable until configured.';

  @override
  String get grace => 'Grace period';

  @override
  String get pending => 'Pending approval';

  @override
  String get revoked => 'Revoked';

  @override
  String get idle => 'Not checked yet';

  @override
  String get permissionSetupTitle => 'Allow keyboard access';

  @override
  String get permissionSetupIntro =>
      'Necaramba needs these macOS permissions to observe keyboard input and apply changes. Enable Necaramba in System Settings (System Preferences on macOS 12) → Privacy & Security / Security & Privacy. Automatic correction also depends on available rules and editor support. If access still appears missing after enabling it, macOS may require you to quit and reopen Necaramba.';

  @override
  String get listenHelp =>
      'Input Monitoring — observe keyboard events for layout switching.';

  @override
  String get postHelp =>
      'Accessibility — send keyboard events to apply a requested change.';

  @override
  String get axHelp =>
      'Accessibility — check the focused editor before changing text.';

  @override
  String get permissionsMissing => 'Keyboard access is incomplete.';

  @override
  String get reviewPermissions => 'Review access';

  @override
  String get permissionsLater => 'Later';

  @override
  String get afterSpace => 'After you press Space';

  @override
  String get autoAvailability =>
      'The switch saves your preference. The status above shows availability. Protected fields and unsupported inputs are skipped.';

  @override
  String get keyboardShortcuts => 'Keyboard shortcuts';

  @override
  String get doubleShift => 'Double Shift';

  @override
  String get doubleShiftHelp =>
      'Convert the last word. Press again to switch it back.';

  @override
  String get additionalCorrections => 'Additional corrections';

  @override
  String get additionalUnavailable =>
      'These corrections are not available yet. Your saved preferences are preserved.';

  @override
  String get runtimeStarting => 'Starting…';

  @override
  String get runtimeUnavailable => 'Automatic correction unavailable';

  @override
  String get runtimeDisconnected => 'Not connected';
}
