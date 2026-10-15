import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @exceptions.
  ///
  /// In en, this message translates to:
  /// **'Exceptions'**
  String get exceptions;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get permissions;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @rules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get rules;

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get account;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Native runtime unavailable'**
  String get unavailable;

  /// No description provided for @errorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This operation is unavailable.'**
  String get errorUnavailable;

  /// No description provided for @errorPermission.
  ///
  /// In en, this message translates to:
  /// **'Permission denied. Review access permissions.'**
  String get errorPermission;

  /// No description provided for @errorConflict.
  ///
  /// In en, this message translates to:
  /// **'Settings changed elsewhere. Review and try again.'**
  String get errorConflict;

  /// No description provided for @errorInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid value. Review your entry.'**
  String get errorInvalid;

  /// No description provided for @errorDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This word already exists.'**
  String get errorDuplicate;

  /// No description provided for @errorIO.
  ///
  /// In en, this message translates to:
  /// **'Unable to save. Your confirmed settings were preserved.'**
  String get errorIO;

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'No response. Reconnect before trying again.'**
  String get errorTimeout;

  /// No description provided for @autoEnabled.
  ///
  /// In en, this message translates to:
  /// **'Automatic layout correction'**
  String get autoEnabled;

  /// No description provided for @typoEnabled.
  ///
  /// In en, this message translates to:
  /// **'Common typos and double capitals'**
  String get typoEnabled;

  /// No description provided for @yoEnabled.
  ///
  /// In en, this message translates to:
  /// **'Restore the letter ё'**
  String get yoEnabled;

  /// No description provided for @singleShiftEnabled.
  ///
  /// In en, this message translates to:
  /// **'Single Shift switches layout'**
  String get singleShiftEnabled;

  /// No description provided for @optionEnabled.
  ///
  /// In en, this message translates to:
  /// **'Option triggers manual correction'**
  String get optionEnabled;

  /// No description provided for @splitShiftEnabled.
  ///
  /// In en, this message translates to:
  /// **'Left + right Shift toggles automation'**
  String get splitShiftEnabled;

  /// No description provided for @plainPasteEnabled.
  ///
  /// In en, this message translates to:
  /// **'⌘ ⇧ V pastes plain text'**
  String get plainPasteEnabled;

  /// No description provided for @soundEnabled.
  ///
  /// In en, this message translates to:
  /// **'Play correction sound'**
  String get soundEnabled;

  /// No description provided for @settingsIntro.
  ///
  /// In en, this message translates to:
  /// **'Your keyboard, your way. Changes are saved on this Mac.'**
  String get settingsIntro;

  /// No description provided for @manualHint.
  ///
  /// In en, this message translates to:
  /// **'Double Shift switches the last word back and forth, or converts selected text. Other Shift combinations work as usual.'**
  String get manualHint;

  /// No description provided for @words.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get words;

  /// No description provided for @applications.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get applications;

  /// No description provided for @addWord.
  ///
  /// In en, this message translates to:
  /// **'Add word'**
  String get addWord;

  /// No description provided for @wordHint.
  ///
  /// In en, this message translates to:
  /// **'1–20 characters; saved locally'**
  String get wordHint;

  /// No description provided for @clearWords.
  ///
  /// In en, this message translates to:
  /// **'Clear words'**
  String get clearWords;

  /// No description provided for @clearQuestion.
  ///
  /// In en, this message translates to:
  /// **'Clear every word exception? This cannot be undone.'**
  String get clearQuestion;

  /// No description provided for @emptyWords.
  ///
  /// In en, this message translates to:
  /// **'No word exceptions yet.'**
  String get emptyWords;

  /// No description provided for @legacy.
  ///
  /// In en, this message translates to:
  /// **'Imported legacy exception — original preserved'**
  String get legacy;

  /// No description provided for @chooseApp.
  ///
  /// In en, this message translates to:
  /// **'Choose .app…'**
  String get chooseApp;

  /// No description provided for @appHint.
  ///
  /// In en, this message translates to:
  /// **'Choose which apps can use automatic correction. Manual shortcuts stay available.'**
  String get appHint;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow automation'**
  String get allow;

  /// No description provided for @deny.
  ///
  /// In en, this message translates to:
  /// **'Disable automation'**
  String get deny;

  /// No description provided for @emptyApps.
  ///
  /// In en, this message translates to:
  /// **'No application rules yet.'**
  String get emptyApps;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @accessIntro.
  ///
  /// In en, this message translates to:
  /// **'Allow each capability explicitly. Secure Input is respected and cannot be disabled here.'**
  String get accessIntro;

  /// No description provided for @listen.
  ///
  /// In en, this message translates to:
  /// **'Listen to keyboard events'**
  String get listen;

  /// No description provided for @post.
  ///
  /// In en, this message translates to:
  /// **'Post replacement events'**
  String get post;

  /// No description provided for @ax.
  ///
  /// In en, this message translates to:
  /// **'Accessibility trust'**
  String get ax;

  /// No description provided for @granted.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get granted;

  /// No description provided for @notGranted.
  ///
  /// In en, this message translates to:
  /// **'Not granted'**
  String get notGranted;

  /// No description provided for @request.
  ///
  /// In en, this message translates to:
  /// **'Request access'**
  String get request;

  /// No description provided for @permissionCheckMissing.
  ///
  /// In en, this message translates to:
  /// **'Checked. macOS has not yet granted access to this copy of Necaramba. If the switches are already on, remove the old Necaramba entry from the relevant list and add the current copy using “+”, then restart the app.'**
  String get permissionCheckMissing;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh status'**
  String get refresh;

  /// No description provided for @secureInput.
  ///
  /// In en, this message translates to:
  /// **'Secure Input'**
  String get secureInput;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @color.
  ///
  /// In en, this message translates to:
  /// **'Header color'**
  String get color;

  /// No description provided for @resetColor.
  ///
  /// In en, this message translates to:
  /// **'Reset color'**
  String get resetColor;

  /// No description provided for @headerImage.
  ///
  /// In en, this message translates to:
  /// **'Header image'**
  String get headerImage;

  /// No description provided for @dropHint.
  ///
  /// In en, this message translates to:
  /// **'Drop an image onto the top bar to personalize it.'**
  String get dropHint;

  /// No description provided for @removeImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get removeImage;

  /// No description provided for @previewImage.
  ///
  /// In en, this message translates to:
  /// **'Refresh image preview'**
  String get previewImage;

  /// No description provided for @sound.
  ///
  /// In en, this message translates to:
  /// **'Correction sound'**
  String get sound;

  /// No description provided for @customSound.
  ///
  /// In en, this message translates to:
  /// **'Custom sound'**
  String get customSound;

  /// No description provided for @defaultSound.
  ///
  /// In en, this message translates to:
  /// **'Default sound'**
  String get defaultSound;

  /// No description provided for @chooseSound.
  ///
  /// In en, this message translates to:
  /// **'Choose sound…'**
  String get chooseSound;

  /// No description provided for @resetSound.
  ///
  /// In en, this message translates to:
  /// **'Reset sound'**
  String get resetSound;

  /// No description provided for @rulesIntro.
  ///
  /// In en, this message translates to:
  /// **'Updates use independently signed rules. Offline operation keeps the installed rules.'**
  String get rulesIntro;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @lastChecked.
  ///
  /// In en, this message translates to:
  /// **'Last checked'**
  String get lastChecked;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @checkRules.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkRules;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Suggest a rule'**
  String get share;

  /// No description provided for @shareIntro.
  ///
  /// In en, this message translates to:
  /// **'Nothing is sent until you review the exact preview and confirm.'**
  String get shareIntro;

  /// No description provided for @word.
  ///
  /// In en, this message translates to:
  /// **'Word'**
  String get word;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @russian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get russian;

  /// No description provided for @feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback (optional)'**
  String get feedback;

  /// No description provided for @previewSubmission.
  ///
  /// In en, this message translates to:
  /// **'Preview submission'**
  String get previewSubmission;

  /// No description provided for @sharePreview.
  ///
  /// In en, this message translates to:
  /// **'Review submission'**
  String get sharePreview;

  /// No description provided for @destination.
  ///
  /// In en, this message translates to:
  /// **'Destination host'**
  String get destination;

  /// No description provided for @modelVersion.
  ///
  /// In en, this message translates to:
  /// **'Rule model version'**
  String get modelVersion;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send this rule'**
  String get send;

  /// No description provided for @statisticsIntro.
  ///
  /// In en, this message translates to:
  /// **'Only aggregate counts are stored. No typed text is collected.'**
  String get statisticsIntro;

  /// No description provided for @estimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated time saved'**
  String get estimate;

  /// No description provided for @formula.
  ///
  /// In en, this message translates to:
  /// **'Estimate v1: layout/manual × 1 s; typo/double capitals/ё × 2 s; undo × 0 s.'**
  String get formula;

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'seconds'**
  String get seconds;

  /// No description provided for @resetCounters.
  ///
  /// In en, this message translates to:
  /// **'Reset counters'**
  String get resetCounters;

  /// No description provided for @resetQuestion.
  ///
  /// In en, this message translates to:
  /// **'Reset aggregate statistics?'**
  String get resetQuestion;

  /// No description provided for @layout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layout;

  /// No description provided for @typo.
  ///
  /// In en, this message translates to:
  /// **'Typos'**
  String get typo;

  /// No description provided for @doubleCaps.
  ///
  /// In en, this message translates to:
  /// **'Double capitals'**
  String get doubleCaps;

  /// No description provided for @yo.
  ///
  /// In en, this message translates to:
  /// **'Letter ё'**
  String get yo;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual corrections'**
  String get manual;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @licenseIntro.
  ///
  /// In en, this message translates to:
  /// **'Manage your license and purchases through the App Store.'**
  String get licenseIntro;

  /// No description provided for @purchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get purchase;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get restore;

  /// No description provided for @manageSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get manageSubscription;

  /// No description provided for @expires.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get expires;

  /// No description provided for @trial.
  ///
  /// In en, this message translates to:
  /// **'Trial'**
  String get trial;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @licensed.
  ///
  /// In en, this message translates to:
  /// **'Licensed'**
  String get licensed;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @aboutIntro.
  ///
  /// In en, this message translates to:
  /// **'Keyboard correction for Russian and English.\nWorks locally on your Mac.\nmacOS 12 and later'**
  String get aboutIntro;

  /// No description provided for @loginStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Status is unavailable. You can request registration again.'**
  String get loginStatusUnknown;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Launch at login'**
  String get login;

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Exports contain aggregate counters and system metadata, never keyboard input. Archives contain your explicitly saved rules and settings.'**
  String get privacy;

  /// No description provided for @exportDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Export diagnostics…'**
  String get exportDiagnostics;

  /// No description provided for @exportArchive.
  ///
  /// In en, this message translates to:
  /// **'Export settings and rules…'**
  String get exportArchive;

  /// No description provided for @importArchive.
  ///
  /// In en, this message translates to:
  /// **'Import settings and rules…'**
  String get importArchive;

  /// No description provided for @importQuestion.
  ///
  /// In en, this message translates to:
  /// **'Import a validated archive? Conflicting or invalid archives are rejected without changing existing data.'**
  String get importQuestion;

  /// No description provided for @localOnly.
  ///
  /// In en, this message translates to:
  /// **'On this Mac'**
  String get localOnly;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Runtime status'**
  String get status;

  /// No description provided for @working.
  ///
  /// In en, this message translates to:
  /// **'Waiting for native confirmation…'**
  String get working;

  /// No description provided for @permissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Permission required'**
  String get permissionRequired;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Automation off'**
  String get off;

  /// No description provided for @licensingBlocked.
  ///
  /// In en, this message translates to:
  /// **'License required'**
  String get licensingBlocked;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateAvailable;

  /// No description provided for @current.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get current;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get checking;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Check failed'**
  String get failed;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @requiresApproval.
  ///
  /// In en, this message translates to:
  /// **'Requires approval in System Settings'**
  String get requiresApproval;

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help & privacy'**
  String get help;

  /// No description provided for @helpText.
  ///
  /// In en, this message translates to:
  /// **'Use Shift shortcuts for manual correction. Automatic correction requires listen and post access. Exceptions remain on this Mac. Network operations require explicit action or configured rule updates. Support and purchase services may be unavailable until configured.'**
  String get helpText;

  /// No description provided for @grace.
  ///
  /// In en, this message translates to:
  /// **'Grace period'**
  String get grace;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get pending;

  /// No description provided for @revoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get revoked;

  /// No description provided for @idle.
  ///
  /// In en, this message translates to:
  /// **'Not checked yet'**
  String get idle;

  /// No description provided for @permissionSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow keyboard access'**
  String get permissionSetupTitle;

  /// No description provided for @permissionSetupIntro.
  ///
  /// In en, this message translates to:
  /// **'Necaramba needs these macOS permissions to observe keyboard input and apply changes. Enable Necaramba in System Settings (System Preferences on macOS 12) → Privacy & Security / Security & Privacy. Automatic correction also depends on available rules and editor support. If access still appears missing after enabling it, macOS may require you to quit and reopen Necaramba.'**
  String get permissionSetupIntro;

  /// No description provided for @listenHelp.
  ///
  /// In en, this message translates to:
  /// **'Input Monitoring — observe keyboard events for layout switching.'**
  String get listenHelp;

  /// No description provided for @postHelp.
  ///
  /// In en, this message translates to:
  /// **'Accessibility — send keyboard events to apply a requested change.'**
  String get postHelp;

  /// No description provided for @axHelp.
  ///
  /// In en, this message translates to:
  /// **'Accessibility — check the focused editor before changing text.'**
  String get axHelp;

  /// No description provided for @permissionsMissing.
  ///
  /// In en, this message translates to:
  /// **'Keyboard access is incomplete.'**
  String get permissionsMissing;

  /// No description provided for @reviewPermissions.
  ///
  /// In en, this message translates to:
  /// **'Review access'**
  String get reviewPermissions;

  /// No description provided for @permissionsLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get permissionsLater;

  /// No description provided for @afterSpace.
  ///
  /// In en, this message translates to:
  /// **'After you press Space'**
  String get afterSpace;

  /// No description provided for @autoAvailability.
  ///
  /// In en, this message translates to:
  /// **'The switch saves your preference. The status above shows availability. Protected fields and unsupported inputs are skipped.'**
  String get autoAvailability;

  /// No description provided for @keyboardShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get keyboardShortcuts;

  /// No description provided for @doubleShift.
  ///
  /// In en, this message translates to:
  /// **'Double Shift'**
  String get doubleShift;

  /// No description provided for @doubleShiftHelp.
  ///
  /// In en, this message translates to:
  /// **'Convert the last word. Press again to switch it back.'**
  String get doubleShiftHelp;

  /// No description provided for @additionalCorrections.
  ///
  /// In en, this message translates to:
  /// **'Additional corrections'**
  String get additionalCorrections;

  /// No description provided for @additionalUnavailable.
  ///
  /// In en, this message translates to:
  /// **'These corrections are not available yet. Your saved preferences are preserved.'**
  String get additionalUnavailable;

  /// No description provided for @runtimeStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get runtimeStarting;

  /// No description provided for @runtimeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Automatic correction unavailable'**
  String get runtimeUnavailable;

  /// No description provided for @runtimeDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get runtimeDisconnected;

  /// No description provided for @layoutShortcut.
  ///
  /// In en, this message translates to:
  /// **'Switch input language'**
  String get layoutShortcut;

  /// No description provided for @layoutShortcutHelp.
  ///
  /// In en, this message translates to:
  /// **'Release the keys to switch. Double Shift always corrects text.'**
  String get layoutShortcutHelp;

  /// No description provided for @shortcutShift.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get shortcutShift;

  /// No description provided for @shortcutAltShift.
  ///
  /// In en, this message translates to:
  /// **'Alt (Option) + Shift'**
  String get shortcutAltShift;

  /// No description provided for @shortcutControlShift.
  ///
  /// In en, this message translates to:
  /// **'Ctrl + Shift'**
  String get shortcutControlShift;

  /// No description provided for @shortcutOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get shortcutOff;

  /// No description provided for @shortcutCommandShift.
  ///
  /// In en, this message translates to:
  /// **'Command + Shift'**
  String get shortcutCommandShift;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
