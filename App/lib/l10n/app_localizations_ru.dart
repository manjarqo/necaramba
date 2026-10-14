// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get settings => 'Настройки';

  @override
  String get exceptions => 'Исключения';

  @override
  String get permissions => 'Доступ';

  @override
  String get appearance => 'Оформление';

  @override
  String get rules => 'Правила';

  @override
  String get statistics => 'Статистика';

  @override
  String get account => 'Лицензия';

  @override
  String get about => 'О программе';

  @override
  String get cancel => 'Отмена';

  @override
  String get confirm => 'Подтвердить';

  @override
  String get save => 'Сохранить';

  @override
  String get delete => 'Удалить';

  @override
  String get reconnect => 'Переподключиться';

  @override
  String get unavailable => 'Нативная служба недоступна';

  @override
  String get errorUnavailable => 'Эта операция недоступна.';

  @override
  String get errorPermission => 'Доступ запрещён. Проверьте разрешения.';

  @override
  String get errorConflict =>
      'Настройки изменились. Проверьте их и повторите действие.';

  @override
  String get errorInvalid => 'Некорректное значение. Проверьте ввод.';

  @override
  String get errorDuplicate => 'Это слово уже существует.';

  @override
  String get errorIO =>
      'Не удалось сохранить. Подтверждённые настройки сохранены.';

  @override
  String get errorTimeout => 'Нет ответа. Переподключитесь перед повтором.';

  @override
  String get autoEnabled => 'Автоматическая коррекция раскладки';

  @override
  String get typoEnabled => 'Опечатки и две начальные заглавные';

  @override
  String get yoEnabled => 'Восстанавливать букву ё';

  @override
  String get singleShiftEnabled => 'Один Shift меняет раскладку';

  @override
  String get optionEnabled => 'Option исправляет вручную';

  @override
  String get splitShiftEnabled =>
      'Левый + правый Shift меняют автоматический режим';

  @override
  String get plainPasteEnabled => '⌘ ⇧ V вставляет простой текст';

  @override
  String get soundEnabled => 'Звук исправления';

  @override
  String get settingsIntro =>
      'Локальные исправления под вашим контролем. Настройки сохраняются на этом Mac.';

  @override
  String get manualHint =>
      'Двойной Shift исправляет слово или выделение и отменяет последнее исправление. Сочетания с Shift работают как обычно.';

  @override
  String get words => 'Слова';

  @override
  String get applications => 'Приложения';

  @override
  String get addWord => 'Добавить слово';

  @override
  String get wordHint => '1–20 символов; сохраняется локально';

  @override
  String get clearWords => 'Очистить слова';

  @override
  String get clearQuestion =>
      'Удалить все исключения для слов? Это действие нельзя отменить.';

  @override
  String get emptyWords => 'Исключений для слов пока нет.';

  @override
  String get legacy => 'Старое импортированное исключение — оригинал сохранён';

  @override
  String get chooseApp => 'Выбрать .app…';

  @override
  String get appHint =>
      'Системный выбор определяет приложения по bundle ID. Правила управляют автоматикой; ручные команды работают отдельно.';

  @override
  String get allow => 'Разрешить автоматику';

  @override
  String get deny => 'Отключить автоматику';

  @override
  String get emptyApps => 'Правил для приложений пока нет.';

  @override
  String get edit => 'Изменить';

  @override
  String get accessIntro =>
      'Разрешите каждую возможность явно. Защищённый ввод учитывается и не отключается здесь.';

  @override
  String get listen => 'Прослушивание событий клавиатуры';

  @override
  String get post => 'Отправка событий замены';

  @override
  String get ax => 'Доступность';

  @override
  String get granted => 'Разрешено';

  @override
  String get notGranted => 'Не разрешено';

  @override
  String get request => 'Запросить доступ';

  @override
  String get permissionCheckMissing =>
      'Проверено. macOS пока не предоставила доступ этой копии Necaramba. Если переключатели уже включены, удалите старую запись Necaramba из соответствующего списка и добавьте текущую копию через «+», затем перезапустите приложение.';

  @override
  String get refresh => 'Обновить статус';

  @override
  String get secureInput => 'Защищённый ввод';

  @override
  String get active => 'Активен';

  @override
  String get inactive => 'Неактивен';

  @override
  String get color => 'Цвет шапки';

  @override
  String get resetColor => 'Сбросить цвет';

  @override
  String get headerImage => 'Изображение шапки';

  @override
  String get dropHint =>
      'Перетащите локальное изображение на шапку. Нативная служба проверит и сохранит его.';

  @override
  String get removeImage => 'Удалить изображение';

  @override
  String get previewImage => 'Обновить изображение';

  @override
  String get sound => 'Звук исправления';

  @override
  String get customSound => 'Пользовательский звук';

  @override
  String get defaultSound => 'Стандартный звук';

  @override
  String get chooseSound => 'Выбрать звук…';

  @override
  String get resetSound => 'Сбросить звук';

  @override
  String get rulesIntro =>
      'Обновления используют независимо подписанные правила. Без сети работают установленные правила.';

  @override
  String get version => 'Версия';

  @override
  String get lastChecked => 'Последняя проверка';

  @override
  String get never => 'Никогда';

  @override
  String get checkRules => 'Проверить обновления';

  @override
  String get share => 'Предложить правило';

  @override
  String get shareIntro =>
      'Данные отправляются только после просмотра точного состава и подтверждения.';

  @override
  String get word => 'Слово';

  @override
  String get language => 'Язык';

  @override
  String get english => 'Английский';

  @override
  String get russian => 'Русский';

  @override
  String get feedback => 'Комментарий (необязательно)';

  @override
  String get previewSubmission => 'Посмотреть перед отправкой';

  @override
  String get sharePreview => 'Проверка отправки';

  @override
  String get destination => 'Сервер назначения';

  @override
  String get modelVersion => 'Версия модели правил';

  @override
  String get send => 'Отправить это правило';

  @override
  String get statisticsIntro =>
      'Сохраняются только суммарные счётчики. Набранный текст не собирается.';

  @override
  String get estimate => 'Оценка сэкономленного времени';

  @override
  String get formula =>
      'Оценка v1: раскладка/вручную × 1 с; опечатки/две заглавные/ё × 2 с; отмена × 0 с.';

  @override
  String get seconds => 'секунд';

  @override
  String get resetCounters => 'Сбросить счётчики';

  @override
  String get resetQuestion => 'Сбросить суммарную статистику?';

  @override
  String get layout => 'Раскладка';

  @override
  String get typo => 'Опечатки';

  @override
  String get doubleCaps => 'Две заглавные';

  @override
  String get yo => 'Буква ё';

  @override
  String get manual => 'Ручные исправления';

  @override
  String get undo => 'Отмена исправления';

  @override
  String get licenseIntro =>
      'Покупки и проверка чеков выполняются нативной службой StoreKit.';

  @override
  String get purchase => 'Купить';

  @override
  String get restore => 'Восстановить покупки';

  @override
  String get manageSubscription => 'Управлять подпиской';

  @override
  String get expires => 'Истекает';

  @override
  String get trial => 'Пробный период';

  @override
  String get expired => 'Истекла';

  @override
  String get licensed => 'Активна';

  @override
  String get blocked => 'Заблокирована';

  @override
  String get unknown => 'Неизвестно';

  @override
  String get aboutIntro =>
      'Necaramba • локальная коррекция ввода RU / EN\nИнтерфейс Flutter · служба Swift\nmacOS 12 и новее';

  @override
  String get login => 'Запускать при входе';

  @override
  String get diagnostics => 'Диагностика';

  @override
  String get privacy =>
      'Диагностика содержит счётчики и системные сведения без клавиатурного ввода. Архив содержит явно сохранённые правила и настройки.';

  @override
  String get exportDiagnostics => 'Экспорт диагностики…';

  @override
  String get exportArchive => 'Экспорт настроек и правил…';

  @override
  String get importArchive => 'Импорт настроек и правил…';

  @override
  String get importQuestion =>
      'Импортировать проверенный архив? Конфликтующие или некорректные архивы отклоняются без изменения текущих данных.';

  @override
  String get localOnly => 'ЛОКАЛЬНО ПО УМОЛЧАНИЮ';

  @override
  String get status => 'Статус службы';

  @override
  String get working => 'Ожидание подтверждения нативной службы…';

  @override
  String get permissionRequired => 'Требуется разрешение';

  @override
  String get off => 'Автоматика отключена';

  @override
  String get licensingBlocked => 'Требуется лицензия';

  @override
  String get updateAvailable => 'Доступно обновление';

  @override
  String get current => 'Актуальны';

  @override
  String get offline => 'Нет сети';

  @override
  String get checking => 'Проверка';

  @override
  String get failed => 'Проверка не удалась';

  @override
  String get enabled => 'Включён';

  @override
  String get disabled => 'Отключён';

  @override
  String get requiresApproval => 'Нужно подтверждение в системных настройках';

  @override
  String get help => 'Справка и конфиденциальность';

  @override
  String get helpText =>
      'Используйте Shift для ручных исправлений. Автоматике нужен доступ к прослушиванию и отправке событий. Исключения остаются на этом Mac. Сетевые операции требуют явного действия или настроенных обновлений правил. Сервисы поддержки и покупок могут быть недоступны до настройки.';

  @override
  String get grace => 'Льготный период';

  @override
  String get pending => 'Ожидает подтверждения';

  @override
  String get revoked => 'Отозвана';

  @override
  String get idle => 'Проверка ещё не выполнялась';

  @override
  String get permissionSetupTitle => 'Разрешите доступ к клавиатуре';

  @override
  String get permissionSetupIntro =>
      'Necaramba нужны разрешения macOS для обработки клавиатурного ввода и применения изменений. Включите Necaramba в Системных настройках → Конфиденциальность и безопасность (macOS 12: Защита и безопасность → Конфиденциальность). Автокоррекция также зависит от доступных правил и поддержки редактора. Если после выдачи разрешения статус не изменился, macOS может потребовать завершить и снова открыть Necaramba.';

  @override
  String get listenHelp =>
      'Мониторинг ввода — отслеживание событий клавиатуры для переключения раскладки.';

  @override
  String get postHelp =>
      'Универсальный доступ — отправка событий клавиатуры для применения запрошенного изменения.';

  @override
  String get axHelp =>
      'Универсальный доступ — проверка активного редактора перед изменением текста.';

  @override
  String get permissionsMissing =>
      'Не все разрешения для клавиатуры предоставлены.';

  @override
  String get reviewPermissions => 'Проверить доступ';

  @override
  String get permissionsLater => 'Позже';
}
