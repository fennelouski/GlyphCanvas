#!/usr/bin/env python3
"""Fill remaining English copies in locale Localizable.strings with curated translations."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from localization_cleanup import (  # noqa: E402
    EN_FILE,
    MOJIBAKE_FIXES,
    ROOT,
    normalize_punctuation,
    parse_strings,
    should_lock_english,
    write_strings,
)

LOCALES = [
    "ar", "de", "es", "fr", "hi", "id", "it", "ja", "ko", "nl",
    "pl", "pt-BR", "pt-PT", "ru", "sv", "tr", "uk", "zh-Hans", "zh-Hant",
]

KEY_EXPORT = "Export…"
KEY_IMPORT = "Import from URL…"
KEY_NO_NET = "No internet connection. Check Wi‑Fi or cellular, then try again."
KEY_WEB = (
    "We load the address directly first. If it’s a webpage, "
    "you can choose an image from the page."
)

# Per-locale curated values (only applied when current value still matches English).
GAP_FILL: dict[str, dict[str, str]] = {
    "ar": {
        KEY_EXPORT: "تصدير…",
        KEY_IMPORT: "استيراد من عنوان URL…",
        KEY_NO_NET: "لا يوجد اتصال بالإنترنت. تحقق من Wi‑Fi أو الشبكة الخلوية، ثم حاول مرة أخرى.",
        KEY_WEB: "نحمّل العنوان مباشرةً أولاً. إذا كانت صفحة ويب، يمكنك اختيار صورة من الصفحة.",
    },
    "de": {
        "Greedy": "Gierig",
        "Format": "Format",
        "Studio": "Studio",
        "STUDIO": "STUDIO",
    },
    "es": {
        "Error": "Error",
        "IRREVERSIBLE": "IRREVERSIBLE",
    },
    "fr": {
        "Format": "Format",
        "Menu": "Menu",
        "Photos": "Photos",
        "Studio": "Studio",
        "STUDIO": "STUDIO",
    },
    "hi": {
        KEY_EXPORT: "निर्यात…",
        KEY_IMPORT: "URL से आयात करें…",
        KEY_NO_NET: "इंटरनेट कनेक्शन नहीं है। Wi‑Fi या सेलुलर जाँचें, फिर पुनः प्रयास करें।",
        KEY_WEB: "हम पहले पता सीधे लोड करते हैं। यदि यह वेबपेज है, तो आप पेज से एक छवि चुन सकते हैं।",
    },
    "id": {
        KEY_EXPORT: "Ekspor…",
        KEY_IMPORT: "Impor dari URL…",
        KEY_NO_NET: "Tidak ada koneksi internet. Periksa Wi‑Fi atau seluler, lalu coba lagi.",
        KEY_WEB: "Kami memuat alamat langsung terlebih dahulu. Jika itu halaman web, Anda dapat memilih gambar dari halaman.",
        "Custom": "Kustom",
    },
    "it": {
        KEY_EXPORT: "Esporta…",
        KEY_IMPORT: "Importa da URL…",
        KEY_NO_NET: "Nessuna connessione Internet. Controlla Wi‑Fi o dati cellulari, poi riprova.",
        KEY_WEB: "Carichiamo prima l’indirizzo direttamente. Se è una pagina web, puoi scegliere un’immagine dalla pagina.",
        "Studio": "Studio",
        "STUDIO": "STUDIO",
    },
    "ja": {},
    "ko": {
        KEY_EXPORT: "\uc218\ucd9c\u2026",
        KEY_IMPORT: "URL에서 가져오기…",
        KEY_NO_NET: "인터넷에 연결되어 있지 않습니다. Wi‑Fi 또는 셀룰러를 확인한 후 다시 시도하세요.",
        KEY_WEB: "먼저 주소를 직접 불러옵니다. 웹페이지인 경우 페이지에서 이미지를 선택할 수 있습니다.",
    },
    "nl": {
        KEY_EXPORT: "Exporteer…",
        KEY_IMPORT: "Importeer van URL…",
        KEY_NO_NET: "Geen internetverbinding. Controleer Wi‑Fi of mobiel netwerk en probeer het opnieuw.",
        KEY_WEB: "We laden het adres eerst rechtstreeks. Als het een webpagina is, kun je een afbeelding op de pagina kiezen.",
        "Stop": "Stoppen",
    },
    "pl": {
        KEY_EXPORT: "Eksportuj…",
        KEY_IMPORT: "Importuj z URL…",
        KEY_NO_NET: "Brak połączenia z Internetem. Sprawdź Wi‑Fi lub sieć komórkową, a następnie spróbuj ponownie.",
        KEY_WEB: "Najpierw wczytujemy adres bezpośrednio. Jeśli to strona internetowa, możesz wybrać obraz ze strony.",
        "Menu": "Menu",
    },
    "pt-BR": {
        KEY_EXPORT: "Exportar…",
        KEY_IMPORT: "Importar de URL…",
        KEY_NO_NET: "Sem conexão com a Internet. Verifique o Wi‑Fi ou os dados móveis e tente novamente.",
        KEY_WEB: "Carregamos o endereço diretamente primeiro. Se for uma página da web, você pode escolher uma imagem na página.",
    },
    "pt-PT": {
        KEY_EXPORT: "Exportar…",
        KEY_IMPORT: "Importar de URL…",
        KEY_NO_NET: "Sem ligação à Internet. Verifique o Wi‑Fi ou os dados móveis e tente novamente.",
        KEY_WEB: "Carregamos o endereço diretamente primeiro. Se for uma página web, pode escolher uma imagem na página.",
    },
    "ru": {
        KEY_EXPORT: "Экспорт…",
        KEY_IMPORT: "Импорт по URL…",
        KEY_NO_NET: "Нет подключения к интернету. Проверьте Wi‑Fi или сотовую сеть и повторите попытку.",
        KEY_WEB: "Сначала мы загружаем адрес напрямую. Если это веб‑страница, вы можете выбрать изображение на странице.",
    },
    "sv": {
        KEY_EXPORT: "Exportera…",
        KEY_IMPORT: "Importera från URL…",
        KEY_NO_NET: "Ingen internetanslutning. Kontrollera Wi‑Fi eller mobilnät och försök igen.",
        KEY_WEB: "Vi laddar adressen direkt först. Om det är en webbsida kan du välja en bild från sidan.",
        "Canvas": "Duk",
        "CASE FILTER": "VERSALFILTER",
        "Match": "Matchning",
        "Format": "Format",
        "Stop": "Stopp",
        "Studio": "Studio",
        "STUDIO": "STUDIO",
        "PARAMETERS": "PARAMETRAR",
    },
    "tr": {
        KEY_EXPORT: "Dışa Aktar…",
        KEY_IMPORT: "URL’den İçe Aktar…",
        KEY_NO_NET: "İnternet bağlantısı yok. Wi‑Fi veya hücresel bağlantıyı kontrol edip tekrar deneyin.",
        KEY_WEB: "Önce adresi doğrudan yüklüyoruz. Bir web sayfasıysa, sayfadan bir görsel seçebilirsiniz.",
    },
    "uk": {
        KEY_EXPORT: "Експортувати…",
        KEY_IMPORT: "Імпорт з URL…",
        KEY_NO_NET: "Немає підключення до інтернету. Перевірте Wi‑Fi або стільникові дані й повторіть спробу.",
        KEY_WEB: "Спочатку ми завантажуємо адресу безпосередньо. Якщо це вебсторінка, ви можете вибрати зображення на сторінці.",
        "Custom": "Власний",
    },
    "zh-Hans": {},
    "zh-Hant": {
        KEY_EXPORT: "輸出…",
        KEY_IMPORT: "從 URL 匯入…",
        KEY_NO_NET: "沒有網路連線。請檢查 Wi‑Fi 或行動網路後再試一次。",
        KEY_WEB: "我們會先直接載入網址。若為網頁，您可以從頁面選擇圖片。",
    },
}

PARTIAL_PREFIXES: dict[str, dict[str, str]] = {
    "it": {"BUFFER: ": "TAMPONE: "},
    "nl": {"BUFFER: ": "Buffer: "},
    "pt-BR": {"BUFFER: ": "TAMPÃO: "},
    "pt-PT": {"BUFFER: ": "TAMPÃO: "},
    "sv": {"Set: ": "Uppsättning: "},
}


def repair_mojibake(text: str) -> str:
    """Fix UTF-8 misread as Latin-1 (line-wise when em dashes block whole-file fix)."""
    lines = []
    changed = False
    for line in text.splitlines():
        try:
            fixed = line.encode("latin-1").decode("utf-8")
        except (UnicodeDecodeError, UnicodeEncodeError):
            fixed = line
        if fixed != line:
            changed = True
        lines.append(fixed)
    if not changed:
        return text
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


def apply_partial_prefixes(locale: str, english: dict[str, str], data: dict[str, str]) -> None:
    prefixes = PARTIAL_PREFIXES.get(locale, {})
    if not prefixes:
        return
    for key, en_val in english.items():
        if should_lock_english(key):
            continue
        if data.get(key) != en_val:
            continue
        for en_prefix, loc_prefix in prefixes.items():
            if en_val.startswith(en_prefix):
                data[key] = en_val.replace(en_prefix, loc_prefix, 1)
                break


def main() -> None:
    english = parse_strings(EN_FILE)
    key_order = list(english.keys())
    updated = 0

    for locale in LOCALES:
        path = ROOT / f"{locale}.lproj" / "Localizable.strings"
        if not path.exists():
            print(f"skip missing {locale}")
            continue

        raw = path.read_text(encoding="utf-8")
        repaired = repair_mojibake(raw)
        if repaired != raw:
            path.write_text(repaired, encoding="utf-8")

        data = dict(english)
        data.update(parse_strings(path))
        fills = GAP_FILL.get(locale, {})
        changed = 0

        for key in key_order:
            en_val = english[key]
            if should_lock_english(key):
                data[key] = en_val
                continue
            cur = data.get(key, en_val)
            if key in fills and cur == en_val:
                data[key] = fills[key]
                changed += 1
            elif cur != en_val:
                data[key] = normalize_punctuation(cur)
            else:
                data[key] = cur

        apply_partial_prefixes(locale, english, data)

        for key in key_order:
            data[key] = normalize_punctuation(data[key])
            for bad, good in MOJIBAKE_FIXES:
                data[key] = data[key].replace(bad, good)

        write_strings(
            path,
            {k: data[k] for k in key_order},
            "GlyphCanvas localization (gap fill).",
        )
        print(f"{locale}: {changed} strings updated")
        updated += changed

    print(f"Done. {updated} total value updates.")


if __name__ == "__main__":
    main()
