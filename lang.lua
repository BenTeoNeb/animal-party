-- lang.lua: every text of the game, in French and in English.
-- Switch on the home screen with a shoulder button (L1/R1) or the L key.

local lang = { current = "fr" }

local TEXTS = {
    fr = {
        title = "LA FÊTE DES ANIMAUX !",
        choose = "Choisis ton personnage",
        choose_game = "Choisis ton jeu", back_short = "retour",
        playmode_learn = "Apprendre", playmode_challenge = "Défi", playmode_item = "Façon de jouer : %s",
        player = "J",
        ready = "Prêt !",
        sound_on = "Son : oui", sound_off = "Son : non",
        comfort_on = "Mouvements doux : oui", comfort_off = "Mouvements doux : non",
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
        mode_fete = "Les enclos", mode_train = "Le train", mode_flash = "Coucou !",
        level_flash_1 = "1 2 3", level_flash_2 = "2 3 4 5", level_flash_3 = "3 4 5 6",
        mode_path = "Le chemin", level_path_1 = "2 + 3", level_path_2 = "5 - 2", level_path_3 = "+ et -",
        mode_oeufs = "Les œufs", level_oeufs_1 = "10 à 19", level_oeufs_2 = "20 à 59", level_oeufs_3 = "jusqu'à 99",
        mode_nid = "Le nid de 10", level_nid_1 = "Remplir", level_nid_2 = "D'un coup", level_nid_3 = "6 + ? = 10",
        level_train_1 = "1 2 3 4 5", level_train_2 = "4 5 6 7 8", level_train_3 = "5 4 3 2 1",
    },
    en = {
        title = "ANIMAL PARTY!",
        choose = "Choose your character",
        choose_game = "Choose your game", back_short = "back",
        playmode_learn = "Learn", playmode_challenge = "Challenge", playmode_item = "Way to play: %s",
        player = "P",
        ready = "Ready!",
        sound_on = "Sound: on", sound_off = "Sound: off",
        comfort_on = "Gentle motion: on", comfort_off = "Gentle motion: off",
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
        mode_fete = "The pens", mode_train = "The train", mode_flash = "Peekaboo!",
        level_flash_1 = "1 2 3", level_flash_2 = "2 3 4 5", level_flash_3 = "3 4 5 6",
        mode_path = "The path", level_path_1 = "2 + 3", level_path_2 = "5 - 2", level_path_3 = "+ and -",
        mode_oeufs = "The eggs", level_oeufs_1 = "10 to 19", level_oeufs_2 = "20 to 59", level_oeufs_3 = "up to 99",
        mode_nid = "The nest of 10", level_nid_1 = "Fill it", level_nid_2 = "All at once", level_nid_3 = "6 + ? = 10",
        level_train_1 = "1 2 3 4 5", level_train_2 = "4 5 6 7 8", level_train_3 = "5 4 3 2 1",
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
