def L(id, name, native, code, words):
    return {"id": id, "name": name, "nativeName": native, "speechCode": code,
            "words": [{"id": f"{id}-{i+1:02d}", "word": w, "meaning": m, "example": e, "exampleMeaning": em}
                      for i, (w, m, e, em) in enumerate(words)]}

LANGUAGES = [
L("es", "Spanish", "Español", "es-ES", [
 ("hola", "hello", "Hola, ¿cómo estás?", "Hello, how are you?"),
 ("gracias", "thank you", "Muchas gracias.", "Thank you very much."),
 ("por favor", "please", "Un café, por favor.", "A coffee, please."),
 ("agua", "water", "Un vaso de agua.", "A glass of water."),
 ("pan", "bread", "El pan está caliente.", "The bread is warm."),
 ("amigo", "friend", "Es mi amigo.", "He is my friend."),
 ("casa", "house", "Mi casa es pequeña.", "My house is small."),
 ("libro", "book", "Leo un libro.", "I am reading a book."),
 ("día", "day", "Buenos días.", "Good morning."),
 ("noche", "night", "Buenas noches.", "Good night."),
 ("sí", "yes", "Sí, claro.", "Yes, of course."),
 ("adiós", "goodbye", "Adiós, hasta mañana.", "Goodbye, see you tomorrow."),
]),
L("fr", "French", "Français", "fr-FR", [
 ("bonjour", "hello", "Bonjour, ça va ?", "Hello, how are you?"),
 ("merci", "thank you", "Merci beaucoup.", "Thank you very much."),
 ("s'il vous plaît", "please", "Un café, s'il vous plaît.", "A coffee, please."),
 ("eau", "water", "Un verre d'eau.", "A glass of water."),
 ("pain", "bread", "Le pain est chaud.", "The bread is warm."),
 ("ami", "friend", "C'est mon ami.", "He is my friend."),
 ("maison", "house", "Ma maison est petite.", "My house is small."),
 ("livre", "book", "Je lis un livre.", "I am reading a book."),
 ("jour", "day", "Quel beau jour !", "What a beautiful day!"),
 ("nuit", "night", "Bonne nuit.", "Good night."),
 ("oui", "yes", "Oui, bien sûr.", "Yes, of course."),
 ("au revoir", "goodbye", "Au revoir, à demain.", "Goodbye, see you tomorrow."),
]),
L("it", "Italian", "Italiano", "it-IT", [
 ("ciao", "hello", "Ciao, come stai?", "Hello, how are you?"),
 ("grazie", "thank you", "Grazie mille.", "Thank you very much."),
 ("per favore", "please", "Un caffè, per favore.", "A coffee, please."),
 ("acqua", "water", "Un bicchiere d'acqua.", "A glass of water."),
 ("pane", "bread", "Il pane è caldo.", "The bread is warm."),
 ("amico", "friend", "È il mio amico.", "He is my friend."),
 ("casa", "house", "La mia casa è piccola.", "My house is small."),
 ("libro", "book", "Leggo un libro.", "I am reading a book."),
 ("giorno", "day", "Buongiorno.", "Good morning."),
 ("notte", "night", "Buonanotte.", "Good night."),
 ("sì", "yes", "Sì, certo.", "Yes, of course."),
 ("arrivederci", "goodbye", "Arrivederci, a domani.", "Goodbye, see you tomorrow."),
]),
]
