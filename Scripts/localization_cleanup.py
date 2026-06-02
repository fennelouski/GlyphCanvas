#!/usr/bin/env python3
"""Normalize localization files: lock technical strings to English, fix punctuation, polish top locales."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "GlyphCanvas"
EN_FILE = ROOT / "en.lproj" / "Localizable.strings"
ENTRY_RE = re.compile(
    r'^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";$',
    re.MULTILINE,
)

LOCALES = [
    "en", "es", "fr", "de", "it", "pt-BR", "pt-PT", "ja", "ko", "zh-Hans",
    "zh-Hant", "ru", "ar", "hi", "tr", "nl", "sv", "pl", "uk", "id",
]
POLISH_LOCALES = {"es", "fr", "de", "ja", "zh-Hans"}

SIMPLE_LOCALIZABLE_PREFIXES = (
    "BUFFER: \\(",
    "Cap: \\(",
    "Estimated size: \\(",
    "Glyphs: \\(",
    "Iterations: \\(",
    "Unique stamps: \\(",
    "Set: \\(",
    "Speed: \\(",
    "Target: \\(",
)

LOCK_SUBSTRINGS = (
    ".navigationTitle(",
    "Toggle(\"",
    "CT_SPEC_",
    "STUDIO_SESSION",
    "viewModel.",
    "manifest.",
    "config.",
    "GalleryArchiveNaming",
    "Self.formatted",
    "characterSetSummaryLine",
    "profileActiveStampCount",
    "activeStamps.count",
    "measuredIterationsPerSecond",
    "iterationsPerSecond",
    "iterationCount",
    "playbackIndex",
    "glyphCount",
    "endPercent",
    "GalleryTheme.marketingVersion",
    "optimizationMode ==",
    "format: .number",
    "r.x),",
    "r.width)",
    "Debug —",
    "Scored \\(",
    "\\(item.stampCount)",
    "\\(recent.stampCount)",
    "https://",
    "V.\\(Gallery",
    "v\\(GalleryTheme",
    "\\(config.fps)",
    "\\(config.frameCount) frames",
    "\\(dims.width)",
    "\\(GalleryArchiveNaming",
    "Fitness (higher better)",
    "Loss (lower better)",
    "Evolution \\(",
    "Glyph \\(",
    "Region \\(",
    "Scored \\(",
    "Use first \\(",
    "Created \\(",
    "Build version v \\(",
)

# Curated user-facing strings (key -> translation). Keys omitted use machine translation + normalize.
POLISH: dict[str, dict[str, str]] = {
    "es": {
        "About GlyphCanvas": "Acerca de GlyphCanvas",
        "Add preset": "Añadir ajuste",
        "ADD PRESET": "AÑADIR AJUSTE",
        "ART GALLERY": "GALERÍA",
        "A–Z": "A–Z",
        "a–z": "a–z",
        "BUILD VERSION": "VERSIÓN",
        "Cancel": "Cancelar",
        "Canvas": "Lienzo",
        "CASE FILTER": "FILTRO DE MAYÚSCULAS",
        "Case filter": "Filtro de mayúsculas",
        "Character set": "Juego de caracteres",
        "Characters": "Caracteres",
        "Check for updates": "Buscar actualizaciones",
        "CHECK FOR UPDATES": "BUSCAR ACTUALIZACIONES",
        "Choose from Library": "Elegir de la biblioteca",
        "Close": "Cerrar",
        "COLLECTED WORKS": "OBRAS GUARDADAS",
        "Continue editing": "Seguir editando",
        "Continue from here": "Continuar desde aquí",
        "Create new artwork": "Crear obra nueva",
        "Custom": "Personalizado",
        "Delete": "Eliminar",
        "DELETE ALL DATA": "ELIMINAR TODOS LOS DATOS",
        "Delete All Data": "Eliminar todos los datos",
        "Delete all data": "Eliminar todos los datos",
        "Delete this artwork?": "¿Eliminar esta obra?",
        "Done": "Listo",
        "Duration (adjusts frame count)": "Duración (ajusta el número de fotogramas)",
        "Edges": "Bordes",
        "Edges mode places ink along outlines instead of matching interior color.": "El modo Bordes coloca tinta sobre los contornos en lugar de igualar el color interior.",
        "Edit stamps": "Editar sellos",
        "Emoji": "Emoji",
        "Encoding": "Codificación",
        "Encoding comparison": "Modo de codificación",
        "ENCODING COMPARISON": "MODO DE CODIFICACIÓN",
        "Error": "Error",
        "Evolutionary": "Evolutivo",
        "Export": "Exportar",
        "Export GIF": "Exportar GIF",
        "Export PNG": "Exportar PNG",
        "Export…": "Exportar…",
        "File size cap": "Límite de tamaño",
        "Files": "Archivos",
        "Format": "Formato",
        "Frame rate": "Velocidad de fotogramas",
        "Frames & duration": "Fotogramas y duración",
        "GALLERY": "GALERÍA",
        "Gallery": "Galería",
        "Genetic": "Genético",
        "Greedy": "Voraz",
        "Image URL": "URL de imagen",
        "Import from URL": "Importar desde URL",
        "Import from URL…": "Importar desde URL…",
        "Export…": "Exportar…",
        "A–Z": "A–Z",
        "a–z": "a–z",
        "IRREVERSIBLE": "IRREVERSIBLE",
        "Load": "Cargar",
        "Load page": "Cargar página",
        "Match": "Coincidencia",
        "mechanical": "mecánico",
        "Mechanical Editor": "Editor mecánico",
        "MECHANICAL EDITOR": "EDITOR MECÁNICO",
        "MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024": "MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024",
        "Menu": "Menú",
        "New archive": "Nuevo archivo",
        "NEW MOSAIC": "NUEVO MOSAICO",
        "Next": "Siguiente",
        "No internet connection. Check Wi‑Fi or cellular, then try again.": "Sin conexión a internet. Comprueba la Wi‑Fi o los datos móviles e inténtalo de nuevo.",
        "No stamps from this input; using defaults.": "No hay sellos en esta entrada; se usan los valores predeterminados.",
        "Nothing to use from this input; falling back to default character set.": "No hay contenido utilizable; se usa el juego de caracteres predeterminado.",
        "Nothing usable in this input; default character set is used.": "No hay contenido utilizable; se usa el juego de caracteres predeterminado.",
        "OK": "OK",
        "Open": "Abrir",
        "OPTIMIZATION MODE": "MODO DE OPTIMIZACIÓN",
        "Optimization mode": "Modo de optimización",
        "PARAMETERS": "PARÁMETROS",
        "Paste": "Pegar",
        "Paste or type text. Unique words (split on whitespace; punctuation trimmed from edges; contractions keep apostrophes) become stamps.": "Pega o escribe texto. Las palabras únicas (separadas por espacios; sin signos en los bordes; las contracciones conservan apóstrofos) se convierten en sellos.",
        "Paste text; unique words become stamps. Whitespace splits tokens; edge punctuation is removed; apostrophes inside words are kept.": "Pega texto; las palabras únicas se convierten en sellos. Los espacios separan tokens; se quitan signos en los bordes; se conservan apóstrofos dentro de las palabras.",
        "PASTE URL": "PEGAR URL",
        "Photos": "Fotos",
        "Platform / utility": "Plataforma / utilidad",
        "Preset": "Ajuste",
        "Profile": "Perfil",
        "Punct": "Signos",
        "Ready for your first": "Listo para tu primera",
        "masterpiece?": "obra maestra?",
        "Recent stamp sets": "Conjuntos de sellos recientes",
        "RECENT STAMP SETS": "SELLOS RECIENTES",
        "Resolution": "Resolución",
        "Resolution (long edge)": "Resolución (lado largo)",
        "Restart animation": "Reiniciar animación",
        "Retry": "Reintentar",
        "REVIEW, EXPORT & ADVANCED": "REVISAR, EXPORTAR Y AVANZADO",
        "Review, export, and advanced": "Revisar, exportar y avanzado",
        "Rotate clockwise": "Girar a la derecha",
        "Rotate counterclockwise": "Girar a la izquierda",
        "Save to gallery": "Guardar en la galería",
        "Select from files": "Elegir archivo",
        "Select from Photos": "Elegir de Fotos",
        "Select Image": "Elegir imagen",
        "SELECT YOUR SOURCE": "ELIGE TU ORIGEN",
        "SETTINGS": "AJUSTES",
        "Settings": "Ajustes",
        "SETUP": "CONFIGURACIÓN",
        "Show optimization debug": "Mostrar depuración de optimización",
        "Show source overlay": "Mostrar imagen original",
        "SOFTWARE UPDATE": "ACTUALIZACIÓN",
        "Stamp source": "Origen de sellos",
        "STAMPS": "SELLOS",
        "Stamps": "Sellos",
        "Stop": "Detener",
        "Studio": "Estudio",
        "STUDIO": "ESTUDIO",
        "Sync data": "Sincronizar datos",
        "SYNC DATA": "SINCRONIZAR DATOS",
        "SYSTEM OUTPUT // ARCHIVE": "SALIDA DEL SISTEMA // ARCHIVO",
        "SYSTEM READY": "SISTEMA LISTO",
        "Take Photo": "Hacer foto",
        "Timeline": "Línea temporal",
        "Timeline range": "Intervalo de línea temporal",
        "Transparent background": "Fondo transparente",
        "Turn your photos into mechanical masterpieces. Start by uploading an image to see the typewriter effect in action.": "Convierte tus fotos en obras maestras mecánicas. Sube una imagen para ver el efecto de máquina de escribir.",
        "Upload a photo to see it transformed into a unique typewriter-style mosaic. Every character is a brushstroke of digital ink.": "Sube una foto para verla convertida en un mosaico único al estilo máquina de escribir. Cada carácter es una pincelada de tinta digital.",
        "We load the address directly first. If it’s a webpage, you can choose an image from the page.": "Cargamos la dirección directamente. Si es una página web, puedes elegir una imagen de la página.",
        "Word source text": "Texto de palabras",
        "Words": "Palabras",
        "Your Canvas is Empty": "Tu lienzo está vacío",
        "Visual computations rendered through mechanical character matrices. Stored in high-fidelity charcoal substrate.": "Cómputos visuales renderizados con matrices de caracteres mecánicas. Almacenados en sustrato de carbón de alta fidelidad.",
    },
    "fr": {
        "About GlyphCanvas": "À propos de GlyphCanvas",
        "Add preset": "Ajouter un préréglage",
        "ADD PRESET": "AJOUTER UN PRÉRÉGLAGE",
        "ART GALLERY": "GALERIE",
        "A–Z": "A–Z",
        "a–z": "a–z",
        "BUILD VERSION": "VERSION",
        "Cancel": "Annuler",
        "Canvas": "Toile",
        "CASE FILTER": "FILTRE DE CASSE",
        "Case filter": "Filtre de casse",
        "Character set": "Jeu de caractères",
        "Characters": "Caractères",
        "Check for updates": "Rechercher des mises à jour",
        "CHECK FOR UPDATES": "RECHERCHER DES MISES À JOUR",
        "Choose from Library": "Choisir dans la bibliothèque",
        "Close": "Fermer",
        "COLLECTED WORKS": "ŒUVRES ENREGISTRÉES",
        "Continue editing": "Poursuivre l’édition",
        "Continue from here": "Continuer à partir d’ici",
        "Create new artwork": "Créer une nouvelle œuvre",
        "Custom": "Personnalisé",
        "Delete": "Supprimer",
        "DELETE ALL DATA": "SUPPRIMER TOUTES LES DONNÉES",
        "Delete All Data": "Supprimer toutes les données",
        "Delete all data": "Supprimer toutes les données",
        "Delete this artwork?": "Supprimer cette œuvre ?",
        "Done": "Terminé",
        "Duration (adjusts frame count)": "Durée (ajuste le nombre d’images)",
        "Edges": "Contours",
        "Edges mode places ink along outlines instead of matching interior color.": "Le mode Contours place l’encre le long des lignes plutôt que d’égaler la couleur intérieure.",
        "Edit stamps": "Modifier les tampons",
        "Emoji": "Emoji",
        "Encoding": "Encodage",
        "Encoding comparison": "Mode d’encodage",
        "ENCODING COMPARISON": "MODE D’ENCODAGE",
        "Error": "Erreur",
        "Evolutionary": "Évolutif",
        "Export": "Exporter",
        "Export GIF": "Exporter en GIF",
        "Export PNG": "Exporter en PNG",
        "Export…": "Exporter…",
        "File size cap": "Limite de taille",
        "Files": "Fichiers",
        "Format": "Format",
        "Frame rate": "Images par seconde",
        "Frames & duration": "Images et durée",
        "GALLERY": "GALERIE",
        "Gallery": "Galerie",
        "Genetic": "Génétique",
        "Greedy": "Glouton",
        "Image URL": "URL de l’image",
        "Import from URL": "Importer depuis une URL",
        "Import from URL…": "Importer depuis une URL…",
        "Export…": "Exporter…",
        "A–Z": "A–Z",
        "a–z": "a–z",
        "IRREVERSIBLE": "IRRÉVERSIBLE",
        "Load": "Charger",
        "Load page": "Charger la page",
        "JULIAN VANCE": "JULIAN VANCE",
        "Match": "Couleur",
        "Mechanical Editor": "Éditeur mécanique",
        "MECHANICAL EDITOR": "ÉDITEUR MÉCANIQUE",
        "MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024": "MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024",
        "Menu": "Menu",
        "New archive": "Nouvelle archive",
        "NEW MOSAIC": "NOUVELLE MOSAÏQUE",
        "Next": "Suivant",
        "No internet connection. Check Wi‑Fi or cellular, then try again.": "Pas de connexion Internet. Vérifiez le Wi‑Fi ou les données cellulaires, puis réessayez.",
        "No stamps from this input; using defaults.": "Aucun tampon dans cette entrée ; valeurs par défaut utilisées.",
        "Nothing to use from this input; falling back to default character set.": "Rien d’utilisable ; jeu de caractères par défaut utilisé.",
        "Nothing usable in this input; default character set is used.": "Rien d’utilisable ; jeu de caractères par défaut utilisé.",
        "OK": "OK",
        "Open": "Ouvrir",
        "OPTIMIZATION MODE": "MODE D’OPTIMISATION",
        "Optimization mode": "Mode d’optimisation",
        "PARAMETERS": "PARAMÈTRES",
        "Paste": "Coller",
        "Paste or type text. Unique words (split on whitespace; punctuation trimmed from edges; contractions keep apostrophes) become stamps.": "Collez ou saisissez du texte. Les mots uniques (séparés par des espaces ; ponctuation retirée aux bords ; apostrophes conservées dans les contractions) deviennent des tampons.",
        "Paste text; unique words become stamps. Whitespace splits tokens; edge punctuation is removed; apostrophes inside words are kept.": "Collez du texte ; les mots uniques deviennent des tampons. Les espaces séparent les jetons ; la ponctuation en bordure est retirée ; les apostrophes dans les mots sont conservées.",
        "PASTE URL": "COLLER L’URL",
        "Photos": "Photos",
        "Platform / utility": "Plateforme / utilitaire",
        "Preset": "Préréglage",
        "Profile": "Profil",
        "Punct": "Ponct.",
        "Ready for your first": "Prêt pour votre première",
        "masterpiece?": "chef-d’œuvre ?",
        "Recent stamp sets": "Jeux de tampons récents",
        "RECENT STAMP SETS": "TAMPONS RÉCENTS",
        "Resolution": "Résolution",
        "Resolution (long edge)": "Résolution (côté long)",
        "Restart animation": "Relancer l’animation",
        "Retry": "Réessayer",
        "REVIEW, EXPORT & ADVANCED": "APERÇU, EXPORT ET AVANCÉ",
        "Review, export, and advanced": "Aperçu, export et avancé",
        "Rotate clockwise": "Pivoter à droite",
        "Rotate counterclockwise": "Pivoter à gauche",
        "Save to gallery": "Enregistrer dans la galerie",
        "Select from files": "Choisir un fichier",
        "Select from Photos": "Choisir dans Photos",
        "Select Image": "Choisir une image",
        "SELECT YOUR SOURCE": "CHOISISSEZ VOTRE SOURCE",
        "SETTINGS": "RÉGLAGES",
        "Settings": "Réglages",
        "SETUP": "CONFIGURATION",
        "Show optimization debug": "Afficher le débogage d’optimisation",
        "Show source overlay": "Afficher l’image source",
        "SOFTWARE UPDATE": "MISE À JOUR",
        "Stamp source": "Source des tampons",
        "STAMPS": "TAMPONS",
        "Stamps": "Tampons",
        "Stop": "Arrêter",
        "Studio": "Studio",
        "STUDIO": "STUDIO",
        "Sync data": "Synchroniser les données",
        "SYNC DATA": "SYNCHRONISER",
        "SYSTEM OUTPUT // ARCHIVE": "SORTIE SYSTÈME // ARCHIVE",
        "SYSTEM READY": "SYSTÈME PRÊT",
        "Take Photo": "Prendre une photo",
        "Timeline": "Chronologie",
        "Timeline range": "Plage de chronologie",
        "Transparent background": "Arrière-plan transparent",
        "Turn your photos into mechanical masterpieces. Start by uploading an image to see the typewriter effect in action.": "Transformez vos photos en chefs-d’œuvre mécaniques. Importez une image pour voir l’effet machine à écrire.",
        "Upload a photo to see it transformed into a unique typewriter-style mosaic. Every character is a brushstroke of digital ink.": "Importez une photo pour la voir devenir une mosaïque unique style machine à écrire. Chaque caractère est un trait d’encre numérique.",
        "We load the address directly first. If it’s a webpage, you can choose an image from the page.": "Nous chargeons d’abord l’adresse directement. Si c’est une page web, vous pouvez choisir une image sur la page.",
        "Word source text": "Texte source (mots)",
        "Words": "Mots",
        "Your Canvas is Empty": "Votre toile est vide",
        "Visual computations rendered through mechanical character matrices. Stored in high-fidelity charcoal substrate.": "Calculs visuels rendus via des matrices de caractères mécaniques. Stockés sur substrat charbon haute fidélité.",
    },
    "de": {
        "About GlyphCanvas": "Über GlyphCanvas",
        "Add preset": "Voreinstellung hinzufügen",
        "ADD PRESET": "VOREINSTELLUNG HINZUFÜGEN",
        "ART GALLERY": "GALERIE",
        "A–Z": "A–Z",
        "a–z": "a–z",
        "BUILD VERSION": "VERSION",
        "Cancel": "Abbrechen",
        "Canvas": "Leinwand",
        "CASE FILTER": "GROSS-/KLEINSCHREIBUNG",
        "Case filter": "Groß-/Kleinschreibung",
        "Character set": "Zeichensatz",
        "Characters": "Zeichen",
        "Check for updates": "Nach Updates suchen",
        "CHECK FOR UPDATES": "NACH UPDATES SUCHEN",
        "Choose from Library": "Aus Mediathek wählen",
        "Close": "Schließen",
        "COLLECTED WORKS": "GESPEICHERTE WERKE",
        "Continue editing": "Weiter bearbeiten",
        "Continue from here": "Hier fortsetzen",
        "Create new artwork": "Neues Werk erstellen",
        "Custom": "Benutzerdefiniert",
        "Delete": "Löschen",
        "DELETE ALL DATA": "ALLE DATEN LÖSCHEN",
        "Delete All Data": "Alle Daten löschen",
        "Delete all data": "Alle Daten löschen",
        "Delete this artwork?": "Dieses Werk löschen?",
        "Done": "Fertig",
        "Duration (adjusts frame count)": "Dauer (passt Bildanzahl an)",
        "Edges": "Kanten",
        "Edges mode places ink along outlines instead of matching interior color.": "Im Kanten-Modus liegt Tinte entlang der Umrisse statt Innenfarben anzugleichen.",
        "Edit stamps": "Stempel bearbeiten",
        "Emoji": "Emoji",
        "Encoding": "Kodierung",
        "Encoding comparison": "Kodierungsmodus",
        "ENCODING COMPARISON": "KODIERUNGSMODUS",
        "Error": "Fehler",
        "Evolutionary": "Evolutionär",
        "Export": "Exportieren",
        "Export GIF": "GIF exportieren",
        "Export PNG": "PNG exportieren",
        "Export…": "Exportieren…",
        "File size cap": "Größenlimit",
        "Files": "Dateien",
        "Format": "Format",
        "Frame rate": "Bildrate",
        "Frames & duration": "Bilder und Dauer",
        "GALLERY": "GALERIE",
        "Gallery": "Galerie",
        "Genetic": "Genetisch",
        "Greedy": "Greedy",
        "Image URL": "Bild-URL",
        "Import from URL": "Von URL importieren",
        "Import from URL…": "Von URL importieren…",
        "Export…": "Exportieren…",
        "A–Z": "A–Z",
        "a–z": "a–z",
        "IRREVERSIBLE": "UNWIDERRUFLICH",
        "Load": "Laden",
        "Load page": "Seite laden",
        "Match": "Farbe",
        "Mechanical Editor": "Mechanischer Editor",
        "MECHANICAL EDITOR": "MECHANISCHER EDITOR",
        "MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024": "MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024",
        "Menu": "Menü",
        "New archive": "Neues Archiv",
        "NEW MOSAIC": "NEUES MOSAIK",
        "Next": "Weiter",
        "No internet connection. Check Wi‑Fi or cellular, then try again.": "Keine Internetverbindung. WLAN oder Mobilfunk prüfen und erneut versuchen.",
        "No stamps from this input; using defaults.": "Keine Stempel in dieser Eingabe; Standardwerte werden verwendet.",
        "Nothing to use from this input; falling back to default character set.": "Nichts Verwendbares; Standard-Zeichensatz wird verwendet.",
        "Nothing usable in this input; default character set is used.": "Nichts Verwendbares; Standard-Zeichensatz wird verwendet.",
        "OK": "OK",
        "Open": "Öffnen",
        "OPTIMIZATION MODE": "OPTIMIERUNGSMODUS",
        "Optimization mode": "Optimierungsmodus",
        "PARAMETERS": "PARAMETER",
        "Paste": "Einfügen",
        "Paste or type text. Unique words (split on whitespace; punctuation trimmed from edges; contractions keep apostrophes) become stamps.": "Text einfügen oder tippen. Eindeutige Wörter (durch Leerzeichen getrennt; Randzeichen entfernt; Apostrophe in Kontraktionen bleiben) werden Stempel.",
        "Paste text; unique words become stamps. Whitespace splits tokens; edge punctuation is removed; apostrophes inside words are kept.": "Text einfügen; eindeutige Wörter werden Stempel. Leerzeichen trennen Tokens; Randzeichen werden entfernt; Apostrophe in Wörtern bleiben.",
        "PASTE URL": "URL EINFÜGEN",
        "Photos": "Fotos",
        "Platform / utility": "Plattform / Dienst",
        "Preset": "Voreinstellung",
        "Profile": "Profil",
        "Punct": "Satzz.",
        "Ready for your first": "Bereit für Ihr erstes",
        "masterpiece?": "Meisterwerk?",
        "Recent stamp sets": "Letzte Stempelsätze",
        "RECENT STAMP SETS": "LETZTE STEMPEL",
        "Resolution": "Auflösung",
        "Resolution (long edge)": "Auflösung (lange Kante)",
        "Restart animation": "Animation neu starten",
        "Retry": "Erneut versuchen",
        "REVIEW, EXPORT & ADVANCED": "VORSCHAU, EXPORT & ERWEITERT",
        "Review, export, and advanced": "Vorschau, Export und Erweitert",
        "Rotate clockwise": "Im Uhrzeigersinn drehen",
        "Rotate counterclockwise": "Gegen den Uhrzeigersinn drehen",
        "Save to gallery": "In Galerie speichern",
        "Select from files": "Aus Dateien wählen",
        "Select from Photos": "Aus Fotos wählen",
        "Select Image": "Bild wählen",
        "SELECT YOUR SOURCE": "QUELLE WÄHLEN",
        "SETTINGS": "EINSTELLUNGEN",
        "Settings": "Einstellungen",
        "SETUP": "EINRICHTUNG",
        "Show optimization debug": "Optimierungs-Debug anzeigen",
        "Show source overlay": "Quellbild einblenden",
        "SOFTWARE UPDATE": "SOFTWARE-UPDATE",
        "Stamp source": "Stempelquelle",
        "STAMPS": "STEMPEL",
        "Stamps": "Stempel",
        "Stop": "Stopp",
        "Studio": "Studio",
        "STUDIO": "STUDIO",
        "Sync data": "Daten synchronisieren",
        "SYNC DATA": "SYNCHRONISIEREN",
        "SYSTEM OUTPUT // ARCHIVE": "SYSTEMAUSGABE // ARCHIV",
        "SYSTEM READY": "SYSTEM BEREIT",
        "Take Photo": "Foto aufnehmen",
        "Timeline": "Zeitleiste",
        "Timeline range": "Zeitleistenbereich",
        "Transparent background": "Transparenter Hintergrund",
        "Turn your photos into mechanical masterpieces. Start by uploading an image to see the typewriter effect in action.": "Verwandeln Sie Fotos in mechanische Meisterwerke. Laden Sie ein Bild hoch, um den Schreibmaschinen-Effekt zu sehen.",
        "Upload a photo to see it transformed into a unique typewriter-style mosaic. Every character is a brushstroke of digital ink.": "Laden Sie ein Foto hoch, um ein einzigartiges Schreibmaschinen-Mosaik zu erhalten. Jedes Zeichen ist ein digitaler Tintenstrich.",
        "We load the address directly first. If it’s a webpage, you can choose an image from the page.": "Die Adresse wird zuerst direkt geladen. Bei einer Webseite können Sie ein Bild von der Seite wählen.",
        "Word source text": "Wortquelltext",
        "Words": "Wörter",
        "Your Canvas is Empty": "Ihre Leinwand ist leer",
        "Visual computations rendered through mechanical character matrices. Stored in high-fidelity charcoal substrate.": "Visuelle Berechnungen über mechanische Zeichenmatrizen. Gespeichert auf hochwertigem Kohle-Substrat.",
    },
    "ja": {
        "About GlyphCanvas": "GlyphCanvas について",
        "Add preset": "プリセットを追加",
        "ADD PRESET": "プリセットを追加",
        "ART GALLERY": "ギャラリー",
        "A–Z": "A–Z",
        "a–z": "a–z",
        "BUILD VERSION": "ビルド",
        "Cancel": "キャンセル",
        "Canvas": "キャンバス",
        "CASE FILTER": "大文字・小文字",
        "Case filter": "大文字・小文字",
        "Character set": "文字セット",
        "Characters": "文字",
        "Check for updates": "アップデートを確認",
        "CHECK FOR UPDATES": "アップデートを確認",
        "Choose from Library": "ライブラリから選択",
        "Close": "閉じる",
        "COLLECTED WORKS": "保存した作品",
        "Continue editing": "編集を続ける",
        "Continue from here": "ここから続ける",
        "Create new artwork": "新しい作品を作成",
        "Custom": "カスタム",
        "Delete": "削除",
        "DELETE ALL DATA": "すべてのデータを削除",
        "Delete All Data": "すべてのデータを削除",
        "Delete all data": "すべてのデータを削除",
        "Delete this artwork?": "この作品を削除しますか？",
        "Done": "完了",
        "Duration (adjusts frame count)": "長さ（フレーム数を調整）",
        "Edges": "エッジ",
        "Edges mode places ink along outlines instead of matching interior color.": "エッジモードは内部色に合わせる代わりに、輪郭に沿ってインクを置きます。",
        "Edit stamps": "スタンプを編集",
        "Emoji": "絵文字",
        "Encoding": "エンコード",
        "Encoding comparison": "エンコード方式",
        "ENCODING COMPARISON": "エンコード方式",
        "Error": "エラー",
        "Evolutionary": "進化的",
        "Export": "書き出す",
        "Export GIF": "GIF を書き出す",
        "Export PNG": "PNG を書き出す",
        "Export…": "書き出す…",
        "File size cap": "ファイルサイズ上限",
        "Files": "ファイル",
        "Format": "形式",
        "Frame rate": "フレームレート",
        "Frames & duration": "フレームと長さ",
        "GALLERY": "ギャラリー",
        "Gallery": "ギャラリー",
        "Genetic": "遺伝的",
        "Greedy": "グリーディ",
        "Image URL": "画像 URL",
        "Import from URL": "URL から読み込む",
        "Import from URL…": "URL から読み込む…",
        "Export…": "書き出す…",
        "A–Z": "A–Z",
        "a–z": "a–z",
        "IRREVERSIBLE": "取り消し不可",
        "Load": "読み込む",
        "Load page": "ページを読み込む",
        "JULIAN VANCE": "JULIAN VANCE",
        "Match": "色合わせ",
        "Mechanical Editor": "メカニカルエディター",
        "MECHANICAL EDITOR": "メカニカルエディター",
        "MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024": "MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024",
        "Menu": "メニュー",
        "New archive": "新しいアーカイブ",
        "NEW MOSAIC": "新しいモザイク",
        "Next": "次へ",
        "No internet connection. Check Wi‑Fi or cellular, then try again.": "インターネットに接続されていません。Wi‑Fi またはモバイルデータを確認して再試行してください。",
        "No stamps from this input; using defaults.": "この入力からスタンプはありません。デフォルトを使用します。",
        "Nothing to use from this input; falling back to default character set.": "使える内容がありません。デフォルトの文字セットを使用します。",
        "Nothing usable in this input; default character set is used.": "使える内容がありません。デフォルトの文字セットを使用します。",
        "OK": "OK",
        "Open": "開く",
        "OPTIMIZATION MODE": "最適化モード",
        "Optimization mode": "最適化モード",
        "PARAMETERS": "パラメータ",
        "Paste": "ペースト",
        "Paste or type text. Unique words (split on whitespace; punctuation trimmed from edges; contractions keep apostrophes) become stamps.": "テキストを貼り付けまたは入力。空白で区切られた一意の単語（端の句読点は除去、短縮形のアポストロフィは保持）がスタンプになります。",
        "Paste text; unique words become stamps. Whitespace splits tokens; edge punctuation is removed; apostrophes inside words are kept.": "テキストを貼り付け。一意の単語がスタンプになります。空白でトークンを分割し、端の句読点を除去、単語内のアポストロフィは保持します。",
        "PASTE URL": "URL を貼り付け",
        "Photos": "写真",
        "Platform / utility": "プラットフォーム / ユーティリティ",
        "Preset": "プリセット",
        "Profile": "プロフィール",
        "Punct": "記号",
        "Ready for your first": "最初の",
        "masterpiece?": "傑作の準備はできましたか？",
        "Recent stamp sets": "最近のスタンプセット",
        "RECENT STAMP SETS": "最近のスタンプ",
        "Resolution": "解像度",
        "Resolution (long edge)": "解像度（長辺）",
        "Restart animation": "アニメーションを再開",
        "Retry": "再試行",
        "REVIEW, EXPORT & ADVANCED": "確認・書き出し・詳細",
        "Review, export, and advanced": "確認・書き出し・詳細",
        "Rotate clockwise": "右回転",
        "Rotate counterclockwise": "左回転",
        "Save to gallery": "ギャラリーに保存",
        "Select from files": "ファイルから選択",
        "Select from Photos": "写真から選択",
        "Select Image": "画像を選択",
        "SELECT YOUR SOURCE": "ソースを選択",
        "SETTINGS": "設定",
        "Settings": "設定",
        "SETUP": "セットアップ",
        "Show optimization debug": "最適化デバッグを表示",
        "Show source overlay": "元画像を重ねて表示",
        "SOFTWARE UPDATE": "ソフトウェア更新",
        "Stamp source": "スタンプのソース",
        "STAMPS": "スタンプ",
        "Stamps": "スタンプ",
        "Stop": "停止",
        "Studio": "スタジオ",
        "STUDIO": "スタジオ",
        "Sync data": "データを同期",
        "SYNC DATA": "同期",
        "SYSTEM OUTPUT // ARCHIVE": "システム出力 // アーカイブ",
        "SYSTEM READY": "システム準備完了",
        "Take Photo": "写真を撮る",
        "Timeline": "タイムライン",
        "Timeline range": "タイムライン範囲",
        "Transparent background": "透明な背景",
        "Turn your photos into mechanical masterpieces. Start by uploading an image to see the typewriter effect in action.": "写真を機械的な傑作に。画像をアップロードしてタイプライター効果を体験してください。",
        "Upload a photo to see it transformed into a unique typewriter-style mosaic. Every character is a brushstroke of digital ink.": "写真をアップロードすると、タイプライター風の独自モザイクに変わります。一文字一文字がデジタルインクの筆致です。",
        "We load the address directly first. If it’s a webpage, you can choose an image from the page.": "まずアドレスを直接読み込みます。Web ページの場合は、ページ内の画像を選べます。",
        "Word source text": "単語ソーステキスト",
        "Words": "単語",
        "Your Canvas is Empty": "キャンバスは空です",
        "Visual computations rendered through mechanical character matrices. Stored in high-fidelity charcoal substrate.": "機械的文字行列で描画された視覚計算。高忠実度の木炭基板に保存。",
    },
    "zh-Hans": {
        "About GlyphCanvas": "关于 GlyphCanvas",
        "Add preset": "添加预设",
        "ADD PRESET": "添加预设",
        "ART GALLERY": "画廊",
        "A–Z": "A–Z",
        "a–z": "a–z",
        "BUILD VERSION": "版本",
        "Cancel": "取消",
        "Canvas": "画布",
        "CASE FILTER": "大小写",
        "Case filter": "大小写",
        "Character set": "字符集",
        "Characters": "字符",
        "Check for updates": "检查更新",
        "CHECK FOR UPDATES": "检查更新",
        "Choose from Library": "从资料库选择",
        "Close": "关闭",
        "COLLECTED WORKS": "已收藏作品",
        "Continue editing": "继续编辑",
        "Continue from here": "从此处继续",
        "Create new artwork": "创建新作品",
        "Custom": "自定义",
        "Delete": "删除",
        "DELETE ALL DATA": "删除所有数据",
        "Delete All Data": "删除所有数据",
        "Delete all data": "删除所有数据",
        "Delete this artwork?": "删除此作品？",
        "Done": "完成",
        "Duration (adjusts frame count)": "时长（调整帧数）",
        "Edges": "边缘",
        "Edges mode places ink along outlines instead of matching interior color.": "边缘模式沿轮廓放置墨迹，而非匹配内部颜色。",
        "Edit stamps": "编辑戳记",
        "Emoji": "表情符号",
        "Encoding": "编码",
        "Encoding comparison": "编码方式",
        "ENCODING COMPARISON": "编码方式",
        "Error": "错误",
        "Evolutionary": "进化",
        "Export": "导出",
        "Export GIF": "导出 GIF",
        "Export PNG": "导出 PNG",
        "Export…": "导出…",
        "File size cap": "文件大小上限",
        "Files": "文件",
        "Format": "格式",
        "Frame rate": "帧率",
        "Frames & duration": "帧与时长",
        "GALLERY": "画廊",
        "Gallery": "画廊",
        "Genetic": "遗传",
        "Greedy": "贪心",
        "Image URL": "图片 URL",
        "Import from URL": "从 URL 导入",
        "Import from URL…": "从 URL 导入…",
        "Export…": "导出…",
        "A–Z": "A–Z",
        "a–z": "a–z",
        "IRREVERSIBLE": "不可撤销",
        "Load": "加载",
        "Load page": "加载页面",
        "Match": "颜色匹配",
        "Mechanical Editor": "机械编辑器",
        "MECHANICAL EDITOR": "机械编辑器",
        "MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024": "MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024",
        "Menu": "菜单",
        "New archive": "新归档",
        "NEW MOSAIC": "新马赛克",
        "Next": "下一步",
        "No internet connection. Check Wi‑Fi or cellular, then try again.": "无网络连接。请检查 Wi‑Fi 或蜂窝网络后重试。",
        "No stamps from this input; using defaults.": "此输入无戳记；使用默认值。",
        "Nothing to use from this input; falling back to default character set.": "无可用内容；回退到默认字符集。",
        "Nothing usable in this input; default character set is used.": "无可用内容；使用默认字符集。",
        "OK": "好",
        "Open": "打开",
        "OPTIMIZATION MODE": "优化模式",
        "Optimization mode": "优化模式",
        "PARAMETERS": "参数",
        "Paste": "粘贴",
        "Paste or type text. Unique words (split on whitespace; punctuation trimmed from edges; contractions keep apostrophes) become stamps.": "粘贴或输入文本。唯一单词（以空白分隔；边缘标点已修剪；缩略保留撇号）将成为戳记。",
        "Paste text; unique words become stamps. Whitespace splits tokens; edge punctuation is removed; apostrophes inside words are kept.": "粘贴文本；唯一单词成为戳记。空白分隔词元；移除边缘标点；保留单词内撇号。",
        "PASTE URL": "粘贴 URL",
        "Photos": "照片",
        "Platform / utility": "平台 / 工具",
        "Preset": "预设",
        "Profile": "个人资料",
        "Punct": "标点",
        "Ready for your first": "准备好创作你的第一幅",
        "masterpiece?": "杰作了吗？",
        "Recent stamp sets": "最近的戳记集",
        "RECENT STAMP SETS": "最近戳记",
        "Resolution": "分辨率",
        "Resolution (long edge)": "分辨率（长边）",
        "Restart animation": "重新开始动画",
        "Retry": "重试",
        "REVIEW, EXPORT & ADVANCED": "预览、导出与高级",
        "Review, export, and advanced": "预览、导出与高级",
        "Rotate clockwise": "顺时针旋转",
        "Rotate counterclockwise": "逆时针旋转",
        "Save to gallery": "保存到画廊",
        "Select from files": "从文件选择",
        "Select from Photos": "从照片选择",
        "Select Image": "选择图片",
        "SELECT YOUR SOURCE": "选择来源",
        "SETTINGS": "设置",
        "Settings": "设置",
        "SETUP": "设置向导",
        "Show optimization debug": "显示优化调试",
        "Show source overlay": "显示原图叠加",
        "SOFTWARE UPDATE": "软件更新",
        "Stamp source": "戳记来源",
        "STAMPS": "戳记",
        "Stamps": "戳记",
        "Stop": "停止",
        "Studio": "工作室",
        "STUDIO": "工作室",
        "Sync data": "同步数据",
        "SYNC DATA": "同步数据",
        "SYSTEM OUTPUT // ARCHIVE": "系统输出 // 归档",
        "SYSTEM READY": "系统就绪",
        "Take Photo": "拍照",
        "Timeline": "时间线",
        "Timeline range": "时间线范围",
        "Transparent background": "透明背景",
        "Turn your photos into mechanical masterpieces. Start by uploading an image to see the typewriter effect in action.": "将照片变成机械杰作。上传图片即可体验打字机效果。",
        "Upload a photo to see it transformed into a unique typewriter-style mosaic. Every character is a brushstroke of digital ink.": "上传照片，看它变成独特的打字机风格马赛克。每个字符都是数字墨迹的一笔。",
        "We load the address directly first. If it’s a webpage, you can choose an image from the page.": "我们会先直接加载地址。若是网页，可从页面中选择图片。",
        "Word source text": "单词源文本",
        "Words": "单词",
        "Your Canvas is Empty": "画布为空",
        "Visual computations rendered through mechanical character matrices. Stored in high-fidelity charcoal substrate.": "通过机械字符矩阵渲染的视觉计算。存储于高保真炭基质。",
    },
}

MOJIBAKE_FIXES = (
    ("â¦", "…"),
    ("â¦", "…"),
    ("â", "–"),
    ("â", "—"),
    ("â", "‑"),
    ("Ã", "×"),
    ("Ã—", "×"),
    ("Ã ", "× "),
    ("Â·", "·"),
    ("Â©", "©"),
    ("1994â2024", "1994–2024"),
    ("1994â2024", "1994–2024"),
    ("AâZ", "A–Z"),
    ("aâz", "a–z"),
    ("WiâFi", "Wi‑Fi"),
    ("WiâFi", "Wi‑Fi"),
    ("itâs", "it’s"),
    ("itâs", "it’s"),
)


def unescape_strings_token(token: str) -> str:
    """Decode standard .strings escapes without mangling UTF-8 characters."""
    out: list[str] = []
    i = 0
    while i < len(token):
        ch = token[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        if i + 1 >= len(token):
            out.append(ch)
            i += 1
            continue
        nxt = token[i + 1]
        if nxt == "n":
            out.append("\n")
            i += 2
        elif nxt == "t":
            out.append("\t")
            i += 2
        elif nxt == "r":
            out.append("\r")
            i += 2
        elif nxt in {'"', "\\"}:
            out.append(nxt)
            i += 2
        else:
            # Swift interpolation and unknown escapes: keep backslash.
            out.append("\\")
            out.append(nxt)
            i += 2
    return "".join(out)


def parse_strings(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for m in ENTRY_RE.finditer(text):
        key = unescape_strings_token(m.group(1))
        val = unescape_strings_token(m.group(2))
        out[key] = val
    return out


def should_lock_english(key: str) -> bool:
    if any(key.startswith(p) for p in SIMPLE_LOCALIZABLE_PREFIXES):
        return False
    return any(s in key for s in LOCK_SUBSTRINGS)


def normalize_punctuation(value: str) -> str:
    out = value
    for bad, good in MOJIBAKE_FIXES:
        out = out.replace(bad, good)
    # Prefer ellipsis only when key context suggests it (value ends with three dots after Export etc.)
    if out.endswith("...") and "Export" in out or out.endswith("..."):
        if "..." in out and "…" not in out:
            out = out.replace("...", "…")
    return out


def translate_mixed_label(english: str, locale: str, prefix_map: dict[str, str]) -> str:
    """Translate known English prefixes before \\( placeholders."""
    for en_prefix, localized in prefix_map.items():
        if english.startswith(en_prefix):
            return english.replace(en_prefix, localized, 1)
    return english


# Prefixes for semi-technical strings that can be partially localized
PARTIAL_PREFIXES = {
    "es": {
        "BUFFER: ": "BÚFER: ",
        "Cap: ": "Límite: ",
        "Estimated size: ": "Tamaño estimado: ",
        "Glyphs: ": "Glifos: ",
        "Iterations: ": "Iteraciones: ",
        "Source: ": "Origen: ",
        "Set: ": "Conjunto: ",
        "Speed: ": "Velocidad: ",
        "Target: ": "Objetivo: ",
        "Unique stamps: ": "Sellos únicos: ",
    },
    "fr": {
        "BUFFER: ": "TAMPON : ",
        "Cap: ": "Plafond : ",
        "Estimated size: ": "Taille estimée : ",
        "Glyphs: ": "Glifes : ",
        "Iterations: ": "Itérations : ",
        "Source: ": "Source : ",
        "Set: ": "Jeu : ",
        "Speed: ": "Vitesse : ",
        "Target: ": "Cible : ",
        "Unique stamps: ": "Tampons uniques : ",
    },
    "de": {
        "BUFFER: ": "PUFFER: ",
        "Cap: ": "Limit: ",
        "Estimated size: ": "Geschätzte Größe: ",
        "Glyphs: ": "Glifes: ",
        "Iterations: ": "Iterationen: ",
        "Source: ": "Quelle: ",
        "Set: ": "Satz: ",
        "Speed: ": "Geschwindigkeit: ",
        "Target: ": "Ziel: ",
        "Unique stamps: ": "Eindeutige Stempel: ",
    },
    "ja": {
        "BUFFER: ": "バッファ: ",
        "Cap: ": "上限: ",
        "Estimated size: ": "推定サイズ: ",
        "Glyphs: ": "グリフ: ",
        "Iterations: ": "反復: ",
        "Source: ": "ソース: ",
        "Set: ": "セット: ",
        "Speed: ": "速度: ",
        "Target: ": "目標: ",
        "Unique stamps: ": "ユニークスタンプ: ",
    },
    "zh-Hans": {
        "BUFFER: ": "缓冲区：",
        "Cap: ": "上限：",
        "Estimated size: ": "估计大小：",
        "Glyphs: ": "字形：",
        "Iterations: ": "迭代：",
        "Source: ": "来源：",
        "Set: ": "集合：",
        "Speed: ": "速度：",
        "Target: ": "目标：",
        "Unique stamps: ": "唯一戳记：",
    },
}


def write_strings(path: Path, entries: dict[str, str], header_comment: str) -> None:
    lines = [
        "/*",
        f" {header_comment}",
        "*/",
        "",
    ]
    for key in entries:
        k = key.replace("\\", "\\\\").replace('"', '\\"')
        v = entries[key].replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'"{k}" = "{v}";')
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    english = parse_strings(EN_FILE)
    key_order = list(english.keys())

    for locale in LOCALES:
        if locale == "en":
            write_strings(
                EN_FILE,
                english,
                "GlyphCanvas English source strings.",
            )
            continue

        locale_file = ROOT / f"{locale}.lproj" / "Localizable.strings"
        current = parse_strings(locale_file) if locale_file.exists() else {}

        cleaned: dict[str, str] = {}
        polish = POLISH.get(locale, {})
        prefixes = PARTIAL_PREFIXES.get(locale, {})

        for key in key_order:
            en_val = english[key]

            if should_lock_english(key):
                cleaned[key] = en_val
                continue

            if locale in POLISH_LOCALES and key in polish:
                cleaned[key] = polish[key]
            elif locale in POLISH_LOCALES and key in current:
                val = current[key]
                if prefixes:
                    val = translate_mixed_label(en_val, locale, prefixes)
                    if val == en_val and key in current:
                        val = normalize_punctuation(current[key])
                else:
                    val = normalize_punctuation(current[key])
                cleaned[key] = val
            elif key in current:
                cleaned[key] = normalize_punctuation(current[key])
            else:
                cleaned[key] = en_val

            cleaned[key] = normalize_punctuation(cleaned[key])

        # Second pass: apply polish again (wins over normalized machine text)
        if locale in POLISH_LOCALES:
            for key, val in polish.items():
                if key in cleaned and not should_lock_english(key):
                    cleaned[key] = val

        # Fix partial-prefix strings for polish locales
        if locale in POLISH_LOCALES:
            for key, en_val in english.items():
                if should_lock_english(key):
                    continue
                if "\\(" in en_val and key not in polish:
                    for en_prefix, loc_prefix in prefixes.items():
                        if en_val.startswith(en_prefix):
                            cleaned[key] = en_val.replace(en_prefix, loc_prefix, 1)
                            break

        header = (
            "GlyphCanvas localization table."
            if locale not in POLISH_LOCALES
            else "GlyphCanvas localization (reviewed for this locale)."
        )
        write_strings(locale_file, {k: cleaned[k] for k in key_order}, header)

        print(f"{locale}: {sum(1 for k in key_order if should_lock_english(k))} locked, "
              f"{len(polish)} polished")

    write_infoplist_strings()
    print("Cleanup complete.")


INFOPLIST_POLISH = {
    "es": {
        "NSCameraUsageDescription": "GlyphCanvas usa la cámara cuando eliges tomar una foto nueva como imagen de origen.",
        "NSPhotoLibraryUsageDescription": "GlyphCanvas necesita acceso a tu fototeca para que puedas elegir una imagen de origen.",
        "NSPhotoLibraryAddUsageDescription": "GlyphCanvas puede guardar imágenes exportadas en tu fototeca cuando eliges Exportar.",
    },
    "fr": {
        "NSCameraUsageDescription": "GlyphCanvas utilise l’appareil photo lorsque vous prenez une nouvelle photo comme image source.",
        "NSPhotoLibraryUsageDescription": "GlyphCanvas a besoin d’accéder à votre photothèque pour choisir une image source.",
        "NSPhotoLibraryAddUsageDescription": "GlyphCanvas peut enregistrer les images exportées dans votre photothèque lorsque vous choisissez Exporter.",
    },
    "de": {
        "NSCameraUsageDescription": "GlyphCanvas verwendet die Kamera, wenn du ein neues Foto als Quellbild aufnimmst.",
        "NSPhotoLibraryUsageDescription": "GlyphCanvas benötigt Zugriff auf deine Mediathek, damit du ein Quellbild auswählen kannst.",
        "NSPhotoLibraryAddUsageDescription": "GlyphCanvas kann exportierte Bilder in deiner Mediathek speichern, wenn du Exportieren wählst.",
    },
    "ja": {
        "NSCameraUsageDescription": "GlyphCanvas は、新しい写真をソース画像として撮影する場合にカメラを使用します。",
        "NSPhotoLibraryUsageDescription": "GlyphCanvas はソース画像を選ぶためにフォトライブラリへのアクセスが必要です。",
        "NSPhotoLibraryAddUsageDescription": "GlyphCanvas は、書き出し時にエクスポートした画像をフォトライブラリに保存できます。",
    },
    "zh-Hans": {
        "NSCameraUsageDescription": "GlyphCanvas 在你选择拍摄新照片作为源图像时会使用相机。",
        "NSPhotoLibraryUsageDescription": "GlyphCanvas 需要访问你的照片图库以便选择源图像。",
        "NSPhotoLibraryAddUsageDescription": "GlyphCanvas 在你选择导出时可将导出的图像保存到照片图库。",
    },
}


def write_infoplist_strings() -> None:
    english = {
        "NSCameraUsageDescription": "GlyphCanvas uses the camera when you choose to take a new photo as the source image.",
        "NSPhotoLibraryUsageDescription": "GlyphCanvas needs access to your photo library so you can pick a source image.",
        "NSPhotoLibraryAddUsageDescription": "GlyphCanvas can save exported images to your photo library when you choose Export.",
    }
    for locale in LOCALES:
        if locale == "en":
            continue
        values = INFOPLIST_POLISH.get(locale)
        if values is None:
            path = ROOT / f"{locale}.lproj" / "InfoPlist.strings"
            if not path.exists():
                continue
            # Keep existing machine translation but normalize via read/write
            current = parse_strings(path)
            values = {k: current.get(k, english[k]) for k in english}
        lines = ["/* Localized privacy usage descriptions */"]
        for key, value in english.items():
            v = values[key]
            v_esc = v.replace("\\", "\\\\").replace('"', '\\"')
            lines.append(f'"{key}" = "{v_esc}";')
        out = ROOT / f"{locale}.lproj" / "InfoPlist.strings"
        out.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
