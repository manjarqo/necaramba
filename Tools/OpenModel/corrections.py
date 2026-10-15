#!/usr/bin/env python3
"""Independently authored bounded typo rules and conservative open-dictionary ё restoration."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODEL = ROOT/'Resources/OpenModel'
# Authored for this project from ordinary spelling knowledge, not copied from
# another correction model, typo dataset, user logs, or evaluation corpus.
AUTHORED_TYPOS = '''
teh the
helllo hello
adn and
recieve receive
recieved received
recieving receiving
adress address
addres address
adres address
wierd weird
becuase because
becasue because
beacuse because
definately definitely
definatly definitely
definetly definitely
seperate separate
seperately separately
seperation separation
occured occurred
occurence occurrence
occurrance occurrence
untill until
tommorow tomorrow
tommorrow tomorrow
tomorow tomorrow
yestarday yesterday
comming coming
begining beginning
beggining beginning
writting writing
writen written
langauge language
lanugage language
grammer grammar
sentance sentence
existance existence
existant existent
maintainance maintenance
maintenence maintenance
enviroment environment
environement environment
goverment government
goverment government
neccessary necessary
necesary necessary
necessery necessary
succesful successful
sucessful successful
succesfully successfully
sucessfully successfully
sucess success
accomodate accommodate
accomodation accommodation
acommodation accommodation
acheive achieve
acheived achieved
acheivement achievement
beleive believe
beleived believed
belive believe
freind friend
freinds friends
wierdly weirdly
thier their
toghether together
togther together
probaly probably
proabably probably
probabaly probably
actualy actually
realy really
usualy usually
finaly finally
especialy especially
basicly basically
publically publicly
responsability responsibility
responsibile responsible
availabe available
avaliable available
avaiable available
compatability compatibility
commited committed
comitted committed
comit commit
conection connection
connetion connection
conector connector
depedency dependency
dependancy dependency
paramter parameter
paramaters parameters
paramater parameter
arguement argument
arguements arguments
funtion function
fucntion function
fuction function
retrun return
retun return
lenght length
widht width
heigth height
interupt interrupt
interuption interruption
repositry repository
respository repository
instalation installation
installtion installation
intial initial
intialize initialize
initalize initialize
privetly privately
здравтсвуйте здравствуйте
здраствуйте здравствуйте
здравствуте здравствуйте
пожалуста пожалуйста
пожалуйсто пожалуйста
спосибо спасибо
спасбио спасибо
превет привет
првиет привет
привте привет
извените извините
извните извините
извеняюсь извиняюсь
сегодян сегодня
севодня сегодня
завтро завтра
вчира вчера
сейчасс сейчас
сейчса сейчас
сичас сейчас
потмоу потому
потм потом
потмо потом
канечно конечно
конешно конечно
кароче короче
пачему почему
почмеу почему
почемуу почему
пачти почти
очен очень
очнь очень
очеь очень
харошо хорошо
хоршо хорошо
хорого хорошо
хорошшо хорошо
правельно правильно
правилно правильно
правльно правильно
неправельно неправильно
неправилно неправильно
возможнасть возможность
возмжность возможность
возмжно возможно
вощможно возможно
интерестно интересно
интерестный интересный
интресно интересно
интресный интересный
приложени приложение
приложние приложение
приложенеи приложение
приложеня приложения
приложенеи приложение
приложенияе приложение
настроки настройки
насторйки настройки
настройик настройки
настройкки настройки
переключени переключение
переключние переключение
переклчение переключение
переключеине переключение
раскалдка раскладка
раскладкка раскладка
раслкадка раскладка
расклдака раскладка
клавитура клавиатура
клавиатруа клавиатура
клавиатруы клавиатуры
клавитаура клавиатура
автоматичсеки автоматически
автомтаически автоматически
автоматичесик автоматически
корекция коррекция
коррекця коррекция
исправлние исправление
исправлеине исправление
исправленеи исправление
работат работает
рабоатет работает
работате работает
работет работает
переодически периодически
периодичсеки периодически
периодичесик периодически
проверкаа проверка
проврека проверка
провекра проверка
провреить проверить
провериь проверить
компютер компьютер
компьтер компьютер
компютера компьютера
компьтера компьютера
браузре браузер
брауезр браузер
браузреа браузера
сообшение сообщение
сообщние сообщение
сообещние сообщение
сообщени сообщение
сообщенеи сообщение
собощение сообщение
сообщеня сообщения
выделеный выделенный
выделеного выделенного
выделеным выделенным
двойнои двойной
двойноой двойной
двоиное двойное
двойноое двойное
нажтаиие нажатие
нажтие нажатие
нажаите нажатие
нажтаие нажатие
нажаитие нажатие
повторноо повторно
повтрно повторно
повторнно повторно
'''

# Explicit preferred spellings, reviewed independently. Plain-е variants may
# already be valid orthography; these are not inferred from unknown words.
AUTHORED_YO = """
елка ёлка
елки ёлки
елку ёлку
елкой ёлкой
елочка ёлочка
елочки ёлочки
елочку ёлочку
ежик ёжик
ежика ёжика
ежики ёжики
ежику ёжику
ежиком ёжиком
береза берёза
березы берёзы
березу берёзу
березой берёзой
березка берёзка
березки берёзки
березку берёзку
зеленый зелёный
зеленая зелёная
зеленое зелёное
зеленые зелёные
зеленого зелёного
зеленому зелёному
зеленым зелёным
зеленых зелёных
желтый жёлтый
желтая жёлтая
желтое жёлтое
желтые жёлтые
желтого жёлтого
желтому жёлтому
желтым жёлтым
желтых жёлтых
черный чёрный
черная чёрная
черное чёрное
черные чёрные
черного чёрного
черному чёрному
черным чёрным
черных чёрных
теплый тёплый
теплая тёплая
теплое тёплое
теплые тёплые
теплого тёплого
теплому тёплому
теплым тёплым
теплых тёплых
твердый твёрдый
твердая твёрдая
твердое твёрдое
твердые твёрдые
твердого твёрдого
твердым твёрдым
твердых твёрдых
четкий чёткий
четкая чёткая
четкое чёткое
четкие чёткие
четкого чёткого
четким чётким
четких чётких
четко чётко
четкость чёткость
"""

def authored_yo_rules(words):
    result = {}
    for line in AUTHORED_YO.splitlines():
        if not line.strip(): continue
        source,target = line.split()
        if (not re.fullmatch(r'[а-я]+',source) or target not in words or 'ё' not in target
            or target.replace('ё','е') != source or source in result):
            raise ValueError(f'Invalid explicit ё preference: {source} -> {target}')
        result[source] = target
    return [{'source':s,'target':t} for s,t in sorted(result.items())]

def yo_rules(words):
    destinations = {}
    for word in words:
        if 'ё' in word:
            folded = word.replace('ё','е')
            destinations.setdefault(folded,set()).add(word)
    return [{'source':source,'target':next(iter(targets))}
            for source,targets in sorted(destinations.items())
            if source not in words and len(targets) == 1]

def validate_typos(pairs, words):
    result = {}
    for source,target in pairs:
        same_script = any(re.fullmatch(pattern, source) and re.fullmatch(pattern, target) for pattern in [r'[a-z]+', r'[а-яё]+'])
        if source in words or target not in words or not same_script:
            raise ValueError(f'Unsafe or unsupported typo: {source} -> {target}')
        if source in result and result[source] != target: raise ValueError('Conflicting typo targets')
        result[source] = target
    return [{'source':s,'target':t} for s,t in sorted(result.items())]

def main():
    raw = (MODEL/'open-v1.json').read_bytes()
    data = json.loads(raw)
    words = set(data['languages']['en']) | set(data['languages']['ru'])
    pairs = [tuple(line.split()) for line in AUTHORED_TYPOS.splitlines() if line.strip()]
    # The draft is explicitly reviewed below; invalid entries must not be silently accepted.
    typos = validate_typos(pairs,words)
    artifact = {'schemaVersion':1,'version':'open-2','typos':typos,
                'yo':authored_yo_rules(set(data['languages']['ru'])),'protectedWords':['ру','все','всё','осел','осёл','небо','нёбо','передохнем','передохнём']}
    result = (json.dumps(artifact,ensure_ascii=False,sort_keys=True,separators=(',',':'))+'\n').encode()
    (MODEL/'corrections.json').write_bytes(result)
    provenance = {'schemaVersion':1,'version':'open-2','artifactSHA256':hashlib.sha256(result).hexdigest(),
       'bytes':len(result),'typoCount':len(typos),'yoCount':len(artifact['yo']),
       'lexiconSHA256':hashlib.sha256(raw).hexdigest(),
       'typoSource':'Independently authored explicit list in Tools/OpenModel/corrections.py; no imported typo dataset or proprietary input.',
       'typoLicense':'GPL-3.0-only (repository license)',
       'yoSource':'Independently authored explicit preferred spellings in AUTHORED_YO; open lexicon used only to validate destinations. GPL-3.0-only.',
       'selection':'Explicit reviewed ё preferences permit standard optional-е spellings; no inferred morphology rules. Ambiguous lexical alternatives protected. No empirical frequencies.'}
    (MODEL/'corrections-provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(provenance,ensure_ascii=False,indent=2))

if __name__ == '__main__': main()
