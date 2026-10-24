-- lang.lua: every text of the game, in French and in English.
-- Switch on the home screen with a shoulder button (L1/R1) or the L key.

local lang = { current = "fr" }

local TEXTS = {
    fr = {
        title = "LA FÊTE DES ANIMAUX !",
        choose = "Choisis ton personnage",
        player = "J",
        ready = "Prêt !",
        sound_on = "Son : oui", sound_off = "Son : non",
        language = "Français",
        choose_short = "choisir", go = "c'est parti !", menu_hint = "menu",
        again_short = "rejouer",
        join = "Joueur 2 : appuie sur un bouton pour jouer aussi !",
        again = "Appuie sur le bouton du bas pour rejouer",
        menu = "Pause",
        resume = "Reprendre", to_title = "Retour à l'accueil", quit = "Quitter le jeu",
        fullscreen_on = "Plein écran : oui", fullscreen_off = "Plein écran : non",
        language_item = "Langue : Français",
        level_1 = "Compter  1 2 3", level_2 = "Ajouter  +", level_3 = "Enlever  -",
        level_item = "Niveau : %s",
    },
    en = {
        title = "ANIMAL PARTY!",
        choose = "Choose your character",
        player = "P",
        ready = "Ready!",
        sound_on = "Sound: on", sound_off = "Sound: off",
        language = "English",
        choose_short = "choose", go = "let's go!", menu_hint = "menu",
        again_short = "play again",
        join = "Player 2: press any button to play too!",
        again = "Press the bottom button to play again",
        menu = "Pause",
        resume = "Resume", to_title = "Back to the start", quit = "Quit the game",
        fullscreen_on = "Fullscreen: on", fullscreen_off = "Fullscreen: off",
        language_item = "Language: English",
        level_1 = "Count  1 2 3", level_2 = "Add  +", level_3 = "Take away  -",
        level_item = "Level: %s",
    },
}

-- The text for `key` in the current language (with %d filled in if given).
function lang.t(key, ...)
    local s = TEXTS[lang.current][key] or TEXTS.fr[key] or key
    if select("#", ...) > 0 then s = string.format(s, ...) end
    return s
end

function lang.toggle()
    lang.current = lang.current == "fr" and "en" or "fr"
end

return lang
