/// Small, independently authored conversational supplement for the local conservative mode.
/// These words are not frequency measurements or corpus qualification evidence. The signed
/// package remains intact; exclusions and ambiguous-source checks still take precedence.
public enum ConservativeVocabulary {
    private static let russian = """
    я ты он она оно мы вы они да нет не ни и а но или что это как где когда зачем почему
    кто кого кому кем чем чего чей моя мой мои твой ваш наш его её их мне меня тебя тебе
    нам вам нас вас у по из за до от на в с к о об для при без под над всё все уже ещё
    вот там тут так же бы был была были быть есть будет будут буду будем можешь могу
    можем можно нужно надо хочу хочешь хочет хотим хорошо плохо спасибо пожалуйста
    привет пока дела дело сегодня завтра вчера сейчас потом снова вместе очень просто
    работает работают работать пишу пишешь написал написать текст слово слова язык
    раскладка исправить исправление проверка готово готов сделал сделать занимаешься
    занимаюсь занят понятно конечно верно действительно давай приветствую здравствуйте
    """
    private static let english = """
    a i am an as at be by do go he if in is it me my no of on or so to up us we you the
    and are for not but can all any how its our out who why yes was were has have had
    did does this that these those what when where which with from your they them their
    here there now then today tomorrow yesterday hello hi thanks please good okay works
    work working text word words language keyboard done write writing help time about
    """
    public static func augment(_ snapshot: RuleSnapshot) -> RuleSnapshot {
        var known = Set(snapshot.lexicon.map { TokenGuard.normalized($0.word) })
        var lexicon = snapshot.lexicon
        for (words, language) in [(russian, Language.russian), (english, Language.english)] {
            for token in words.split(whereSeparator: { $0.isWhitespace }) {
                let word = String(token)
                if known.insert(TokenGuard.normalized(word)).inserted {
                    lexicon.append(.init(word: word, language: language, frequencyBand: 1))
                }
            }
        }
        return .init(modelVersion: snapshot.modelVersion, lexicon: lexicon, typos: snapshot.typos,
            yoRules: snapshot.yoRules, protectedTokens: snapshot.protectedTokens, mappings: snapshot.mappings)
    }
}
