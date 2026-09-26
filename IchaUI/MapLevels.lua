-- IchaUI MapLevels: zone level ranges on the world map (Lua 5.0 / 1.12).
-- Hover a zone on a continent map to see its level range, faction, fishing
-- skill, instances and raids. Works on the stock map and IchaUI's windowed map.
-- Settings: IchaUIDB.worldmap.levels / levelInst / levelRaids / levelPvP / levelFish.
--
-- Based on LevelRange [Turtle] 2.2.0 by Bull3t, Tenyar97, rado-boy, blehz,
-- rafacc87, Diginfotek and Spartelfant (https://github.com/Spartelfant/LevelRange-Turtle).
-- Copyright (c) 2006 Philip Hughes (Bull3t); translations (c) Rafael Calafell (rafacc87),
-- Diginfotek. Original license: "An unlimited license to use, reproduce and copy
-- this work is granted, on the condition that the licensee accepts all
-- responsibility and liability for any damage that may arise from the use of this AddOn."

local function installIchaUIMapLevels()
    -- Zone, instance and faction names per client locale (from LevelRange's Locale files).
    local LOC = {
        enUS = {
            ["ALLIANCE"] = "Alliance",
            ["HORDE"] = "Horde",
            ["CONTESTED"] = "Contested",
            ["FRIENDLY"] = "Friendly",
            ["HOSTILE"] = "Hostile",
            ["1KNEEDLES"] = "Thousand Needles",
            ["ALTERAC"] = "Alterac Mountains",
            ["ARATHI"] = "Arathi Highlands",
            ["ASHENVALE"] = "Ashenvale",
            ["AZSHARA"] = "Azshara",
            ["BADLANDS"] = "Badlands",
            ["BARRENS"] = "The Barrens",
            ["BLASTEDLANDS"] = "Blasted Lands",
            ["BURNINGSTEPPE"] = "Burning Steppes",
            ["DARKSHORE"] = "Darkshore",
            ["DEADWINDPASS"] = "Deadwind Pass",
            ["DESOLACE"] = "Desolace",
            ["DUNMOROGH"] = "Dun Morogh",
            ["DUROTAR"] = "Durotar",
            ["DUSKWOOD"] = "Duskwood",
            ["DUSTWALLOW"] = "Dustwallow Marsh",
            ["EASTERNPLAGUE"] = "Eastern Plaguelands",
            ["ELWYNN"] = "Elwynn Forest",
            ["FELWOOD"] = "Felwood",
            ["FERALAS"] = "Feralas",
            ["HILLSBRAD"] = "Hillsbrad Foothills",
            ["HINTERLANDS"] = "The Hinterlands",
            ["LOCHMODAN"] = "Loch Modan",
            ["MOONGLADE"] = "Moonglade",
            ["MULGORE"] = "Mulgore",
            ["REDRIDGE"] = "Redridge Mountains",
            ["SEARINGGORGE"] = "Searing Gorge",
            ["SILITHUS"] = "Silithus",
            ["SILVERPINE"] = "Silverpine Forest",
            ["SORROWS"] = "Swamp of Sorrows",
            ["STONETALON"] = "Stonetalon Mountains",
            ["STRANGLETHORN"] = "Stranglethorn Vale",
            ["TANARIS"] = "Tanaris",
            ["TELDRASSIL"] = "Teldrassil",
            ["TIRISFAL"] = "Tirisfal Glades",
            ["UNGOROCRATER"] = "Un'Goro Crater",
            ["WESTERNPLAGUE"] = "Western Plaguelands",
            ["WESTFALL"] = "Westfall",
            ["WETLANDS"] = "Wetlands",
            ["WINTERSPRING"] = "Winterspring",
            ["BLACKSTONEISLAND"] = "Blackstone Island",
            ["GILLIJIM"] = "Gillijim's Isle",
            ["GILNEAS"] = "Gilneas",
            ["HYJAL"] = "Hyjal",
            ["LAPIDIS"] = "Lapidis Isle",
            ["SCARLETENCLAVE"] = "Scarlet Enclave",
            ["TELABIM"] = "Tel'Abim",
            ["THALASSIANHIGHLANDS"] = "Thalassian Highlands",
            ["GRIMREACHES"] = "Grim Reaches",
            ["NORTHWIND"] = "Northwind",
            ["BALOR"] = "Balor",
            ["DARNASSUS"] = "Darnassus",
            ["IRONFORGE"] = "Ironforge",
            ["ORGRIMMAR"] = "Orgrimmar",
            ["STORMWIND"] = "Stormwind City",
            ["THUNDERBLUFF"] = "Thunder Bluff",
            ["UNDERCITY"] = "Undercity",
            ["ALAHTHALAS"] = "Alah'Thalas",
            ["RUINSOFZULRASAZ"] = "Ruins of Zul'rasaz",
            ["TIRISFALUPLANDS"] = "Tirisfal Uplands",
            ["SLICKWICKOILRIG"] = "Slickwick Oil Rig",
            ["RUGFORDSMOUNTAINREST"] = "Rugford's Mountain Rest",
            ["EARTHENRING"] = "Earthen Ring",
            ["INSTANCESTEXT"] = "Instances:",
            ["BLACKFATHOMDEEPS"] = "Blackfathom Deeps",
            ["BLACKROCKDEPTH"] = "Blackrock Depths",
            ["BLACKROCKSPIRE"] = "Blackrock Spire",
            ["DEADMINES"] = "Deadmines",
            ["DIREMAUL"] = "Dire Maul",
            ["GNOMEREGAN"] = "Gnomeregan",
            ["MARAUDON"] = "Maraudon",
            ["RAGEFIRECHASM"] = "Ragefire Chasm",
            ["RAZORFENDOWNS"] = "Razorfen Downs",
            ["RAZORFENKRAUL"] = "Razorfen Kraul",
            ["SCARLETMONASTERY"] = "The Scarlet Monastery",
            ["SCHOLOMANCE"] = "Scholomance",
            ["SHADOWFANGKEEP"] = "Shadowfang Keep",
            ["STOCKADES"] = "The Stockades",
            ["STRATHOLME"] = "Stratholme",
            ["SUNKENTEMPLE"] = "The Sunken Temple",
            ["ULDAMAN"] = "Uldaman",
            ["WAILINGCAVERNS"] = "Wailing Caverns",
            ["ZULFARRAK"] = "Zul'Farrak",
            ["COTBLACKMORASS"] = "Caverns of Time: The Black Morass",
            ["CRESCENTGROVE"] = "The Crescent Grove",
            ["GILNEASCITY"] = "Gilneas City",
            ["HATEFORGEQUARRY"] = "Hateforge Quarry",
            ["KARAZHANCRYPT"] = "Karazhan Crypt",
            ["STORMWINDVAULT"] = "Stormwind Vault",
            ["STORMWROUGHTRUINS"] = "Stormwrought Ruins",
            ["DRAGONMAWRETREAT"] = "Dragonmaw Retreat",
            ["RAIDSTEXT"] = "Raids:",
            ["NAXXRAMAS"] = "Naxxramas",
            ["ONYXIASLAIR"] = "Onyxia's Lair",
            ["RUINSAHNQIRAJ"] = "Ruins of Ahn'Qiraj",
            ["TEMPLEAHNQIRAJ"] = "Temple of Ahn'Qiraj",
            ["ZULGURUB"] = "Zul'Gurub",
            ["EMERALDSANCTUM"] = "Emerald Sanctum",
            ["LOWERKARAZHANHALLS"] = "Lower Karazhan Halls",
            ["LEVELS"] = "Levels %d - %d",
            ["FLEVEL"] = "Fishing Level %d",
        },
        deDE = {
            ["ALLIANCE"] = "Allianz",
            ["HORDE"] = "Horde",
            ["CONTESTED"] = "Umstrittenes Gebiet",
            ["FRIENDLY"] = "Freundlich",
            ["HOSTILE"] = "Feindselig",
            ["1KNEEDLES"] = "Tausend Nadeln",
            ["ALTERAC"] = "Alteracgebirge",
            ["ARATHI"] = "Arathihochland",
            ["ASHENVALE"] = "Eschental",
            ["AZSHARA"] = "Azshara",
            ["BADLANDS"] = "Ödland",
            ["BARRENS"] = "Brachland",
            ["BLASTEDLANDS"] = "Verwüstete Lande",
            ["BURNINGSTEPPE"] = "Brennende Steppe",
            ["DARKSHORE"] = "Dunkelküste",
            ["DEADWINDPASS"] = "Gebirgspass der Totenwinde",
            ["DESOLACE"] = "Desolace",
            ["DUNMOROGH"] = "Dun Morogh",
            ["DUROTAR"] = "Durotar",
            ["DUSKWOOD"] = "Dämmerwald",
            ["DUSTWALLOW"] = "Düstermarschen",
            ["EASTERNPLAGUE"] = "Östliche Pestländer",
            ["ELWYNN"] = "Wald von Elwynn",
            ["FELWOOD"] = "Teufelswald",
            ["FERALAS"] = "Feralas",
            ["HILLSBRAD"] = "Vorgebirge des Hügellandes",
            ["HINTERLANDS"] = "Hinterland",
            ["LOCHMODAN"] = "Loch Modan",
            ["MOONGLADE"] = "Mondlichtung",
            ["MULGORE"] = "Mulgore",
            ["REDRIDGE"] = "Rotkammgebirge",
            ["SEARINGGORGE"] = "Sengende Schlucht",
            ["SILITHUS"] = "Silithus",
            ["SILVERPINE"] = "Silberwald",
            ["SORROWS"] = "Sümpfe des Elends",
            ["STONETALON"] = "Steinkrallengebirge",
            ["STRANGLETHORN"] = "Schlingendorntal",
            ["TANARIS"] = "Tanaris",
            ["TELDRASSIL"] = "Teldrassil",
            ["TIRISFAL"] = "Tirisfal",
            ["UNGOROCRATER"] = "Un'Goro-Krater",
            ["WESTERNPLAGUE"] = "Westliche Pestländer",
            ["WESTFALL"] = "Westfall",
            ["WETLANDS"] = "Sumpfland",
            ["WINTERSPRING"] = "Winterquell",
            ["BLACKSTONEISLAND"] = "Schwarzstein Insel",
            ["GILLIJIM"] = "Gillijims Insel",
            ["GILNEAS"] = "Gilneas",
            ["HYJAL"] = "Hyjal",
            ["LAPIDIS"] = "Insel des Doktor Lapidis",
            ["SCARLETENCLAVE"] = "Scharlachrote Enklave",
            ["TELABIM"] = "Tel'Abim",
            ["THALASSIANHIGHLANDS"] = "Thalassisches Hochland",
            ["GRIMREACHES"] = "Düstere Weiten",
            ["NORTHWIND"] = "Nordwind",
            ["BALOR"] = "Balor",
            ["DARNASSUS"] = "Darnassus",
            ["IRONFORGE"] = "Eisenschmiede",
            ["ORGRIMMAR"] = "Orgrimmmar",
            ["STORMWIND"] = "Sturnwind",
            ["THUNDERBLUFF"] = "Donnerfels",
            ["UNDERCITY"] = "Unterstadt",
            ["ALAHTHALAS"] = "Alah'Thalas",
            ["RUINSOFZULRASAZ"] = "Ruins of Zul'rasaz",
            ["TIRISFALUPLANDS"] = "Tirisfal Uplands",
            ["SLICKWICKOILRIG"] = "Slickwick Oil Rig",
            ["RUGFORDSMOUNTAINREST"] = "Rugford's Mountain Rest",
            ["EARTHENRING"] = "Earthen Ring",
            ["INSTANCESTEXT"] = "Instanzen:",
            ["BLACKFATHOMDEEPS"] = "Blackfathom Deeps",
            ["BLACKROCKDEPTH"] = "Blackrock Depths",
            ["BLACKROCKSPIRE"] = "Blackrock Spire",
            ["DEADMINES"] = "Deadmines",
            ["DIREMAUL"] = "Dire Maul",
            ["GNOMEREGAN"] = "Gnomeregan",
            ["MARAUDON"] = "Maraudon",
            ["RAGEFIRECHASM"] = "Ragefire Chasm",
            ["RAZORFENDOWNS"] = "Razorfen Downs",
            ["RAZORFENKRAUL"] = "Razorfen Kraul",
            ["SCARLETMONASTERY"] = "The Scarlet Monastery",
            ["SCHOLOMANCE"] = "Scholomance",
            ["SHADOWFANGKEEP"] = "Shadowfang Keep",
            ["STOCKADES"] = "The Stockades",
            ["STRATHOLME"] = "Stratholme",
            ["SUNKENTEMPLE"] = "The Sunken Temple",
            ["ULDAMAN"] = "Uldaman",
            ["WAILINGCAVERNS"] = "Wailing Caverns",
            ["ZULFARRAK"] = "Zul'Farrak",
            ["COTBLACKMORASS"] = "Caverns of Time: The Black Morass",
            ["CRESCENTGROVE"] = "The Crescent Grove",
            ["GILNEASCITY"] = "Gilneas City",
            ["HATEFORGEQUARRY"] = "Hateforge Quarry",
            ["KARAZHANCRYPT"] = "Karazhan Crypt",
            ["STORMWINDVAULT"] = "Stormwind Vault",
            ["STORMWROUGHTRUINS"] = "Stormwrought Ruins",
            ["DRAGONMAWRETREAT"] = "Dragonmaw Retreat",
            ["RAIDSTEXT"] = "Schlachtzüge:",
            ["NAXXRAMAS"] = "Naxxramas",
            ["ONYXIASLAIR"] = "Onyxia's Lair",
            ["RUINSAHNQIRAJ"] = "Ruins of Ahn'Qiraj",
            ["TEMPLEAHNQIRAJ"] = "Temple of Ahn'Qiraj",
            ["ZULGURUB"] = "Zul'Gurub",
            ["EMERALDSANCTUM"] = "Emerald Sanctum",
            ["LOWERKARAZHANHALLS"] = "Lower Karazhan Halls",
            ["LEVELS"] = "Stufen %d - %d",
            ["FLEVEL"] = "Angelniveau %d",
        },
        esES = {
            ["ALLIANCE"] = "Alianza",
            ["HORDE"] = "Horda",
            ["CONTESTED"] = "Zona en disputa",
            ["FRIENDLY"] = "Amistoso",
            ["HOSTILE"] = "Hostil",
            ["1KNEEDLES"] = "Las Mil Agujas",
            ["ALTERAC"] = "Montañas de Alterac",
            ["ARATHI"] = "Tierras Altas de Arathi",
            ["ASHENVALE"] = "Vallefresno",
            ["AZSHARA"] = "Azshara",
            ["BADLANDS"] = "Tierras Inhóspitas",
            ["BARRENS"] = "Los Baldíos",
            ["BLASTEDLANDS"] = "Tierras Devastadas",
            ["BURNINGSTEPPE"] = "Las Estepas Ardientes",
            ["DARKSHORE"] = "Costa Oscura",
            ["DEADWINDPASS"] = "Paso de la Muerte",
            ["DESOLACE"] = "Desolace",
            ["DUNMOROGH"] = "Dun Morogh",
            ["DUROTAR"] = "Durotar",
            ["DUSKWOOD"] = "Bosque del Ocaso",
            ["DUSTWALLOW"] = "Marjal Revolcafango",
            ["EASTERNPLAGUE"] = "Tierras de la Peste del Este",
            ["ELWYNN"] = "Bosque de Elwynn",
            ["FELWOOD"] = "Frondavil",
            ["FERALAS"] = "Feralas",
            ["HILLSBRAD"] = "Laderas de Trabalomas",
            ["HINTERLANDS"] = "Tierras del Interior",
            ["LOCHMODAN"] = "Loch Modan",
            ["MOONGLADE"] = "Claro de la Luna",
            ["MULGORE"] = "Mulgore",
            ["REDRIDGE"] = "Montañas Crestagrana",
            ["SEARINGGORGE"] = "La Garganta de Fuego",
            ["SILITHUS"] = "Silithus",
            ["SILVERPINE"] = "Bosque de Argénteos",
            ["SORROWS"] = "Pantano de las Penas",
            ["STONETALON"] = "Montañas de Colina Roca",
            ["STRANGLETHORN"] = "Vega de Tuercespina",
            ["TANARIS"] = "Tanaris",
            ["TELDRASSIL"] = "Teldrassil",
            ["TIRISFAL"] = "Claros de Tirisfal",
            ["UNGOROCRATER"] = "Crater Un'Goro",
            ["WESTERNPLAGUE"] = "Tierras de la Peste del Oeste",
            ["WESTFALL"] = "Páramos del Poniente",
            ["WETLANDS"] = "Los Humedales",
            ["WINTERSPRING"] = "Cuna del Invierno",
            ["BLACKSTONEISLAND"] = "Isla Piedra Negra",
            ["GILLIJIM"] = "Isla de Gillijim",
            ["GILNEAS"] = "Gilneas",
            ["HYJAL"] = "Hyjal",
            ["LAPIDIS"] = "Isla Lapidis",
            ["SCARLETENCLAVE"] = "Enclave Escarlata",
            ["TELABIM"] = "Tel'Abim",
            ["THALASSIANHIGHLANDS"] = "Tierras Altas Thalassianas",
            ["GRIMREACHES"] = "Alcances Sombríos",
            ["NORTHWIND"] = "Viento del Norte",
            ["BALOR"] = "Balor",
            ["DARNASSUS"] = "Darnassus",
            ["IRONFORGE"] = "Forjaz",
            ["ORGRIMMAR"] = "Orgrimmar",
            ["STORMWIND"] = "Ciudad de Ventormenta",
            ["THUNDERBLUFF"] = "Cima del Trueno",
            ["UNDERCITY"] = "Entrañas",
            ["ALAHTHALAS"] = "Alah'Thalas",
            ["RUINSOFZULRASAZ"] = "Ruins of Zul'rasaz",
            ["TIRISFALUPLANDS"] = "Tirisfal Uplands",
            ["SLICKWICKOILRIG"] = "Slickwick Oil Rig",
            ["RUGFORDSMOUNTAINREST"] = "Rugford's Mountain Rest",
            ["EARTHENRING"] = "Earthen Ring",
            ["INSTANCESTEXT"] = "Mazmorras:",
            ["BLACKFATHOMDEEPS"] = "Cavernas de Brazanegra",
            ["BLACKROCKDEPTH"] = "Profundidades de Roca Negra",
            ["BLACKROCKSPIRE"] = "Cumbre de Roca Negra",
            ["DEADMINES"] = "Las Minas de la Muerte",
            ["DIREMAUL"] = "La Masacre",
            ["GNOMEREGAN"] = "Gnomeregan",
            ["MARAUDON"] = "Maraudon",
            ["RAGEFIRECHASM"] = "Sima Ígnea",
            ["RAZORFENDOWNS"] = "Zahúrda Rojocieno",
            ["RAZORFENKRAUL"] = "Horado Rajacieno",
            ["SCARLETMONASTERY"] = "Monasterio Escarlata",
            ["SCHOLOMANCE"] = "Scholomance",
            ["SHADOWFANGKEEP"] = "Castillo de Colmillo Oscuro",
            ["STOCKADES"] = "Mazmorras de Ventormenta",
            ["STRATHOLME"] = "Stratholme",
            ["SUNKENTEMPLE"] = "The Sunken Temple",
            ["ULDAMAN"] = "Uldaman",
            ["WAILINGCAVERNS"] = "Cuevas de los Lamentos",
            ["ZULFARRAK"] = "Zul'Farrak",
            ["COTBLACKMORASS"] = "Caverns of Time: The Black Morass",
            ["CRESCENTGROVE"] = "The Crescent Grove",
            ["GILNEASCITY"] = "Gilneas City",
            ["HATEFORGEQUARRY"] = "Hateforge Quarry",
            ["KARAZHANCRYPT"] = "Karazhan Crypt",
            ["STORMWINDVAULT"] = "Stormwind Vault",
            ["STORMWROUGHTRUINS"] = "Stormwrought Ruins",
            ["DRAGONMAWRETREAT"] = "Dragonmaw Retreat",
            ["RAIDSTEXT"] = "Bandas:",
            ["NAXXRAMAS"] = "Naxxramas",
            ["ONYXIASLAIR"] = "Guarida de Onyxia",
            ["RUINSAHNQIRAJ"] = "Ruinas de Ahn'Qiraj",
            ["TEMPLEAHNQIRAJ"] = "Templo de Ahn'Qiraj",
            ["ZULGURUB"] = "Zul'Gurub",
            ["EMERALDSANCTUM"] = "Emerald Sanctum",
            ["LOWERKARAZHANHALLS"] = "Lower Karazhan Halls",
            ["LEVELS"] = "Niveles %d - %d",
            ["FLEVEL"] = "Nivel de pesca %d",
        },
        frFR = {
            ["ALLIANCE"] = "Alliance",
            ["HORDE"] = "Horde",
            ["CONTESTED"] = "Contesté",
            ["FRIENDLY"] = "Amicale",
            ["HOSTILE"] = "Hostile",
            ["1KNEEDLES"] = "Mille Pointes",
            ["ALTERAC"] = "Montagnes d'Alterac",
            ["ARATHI"] = "Hautes-Terres Arathies",
            ["ASHENVALE"] = "Orneval",
            ["AZSHARA"] = "Azshara",
            ["BADLANDS"] = "Terres Ingrates",
            ["BARRENS"] = "Les Tarides",
            ["BLASTEDLANDS"] = "Terres Foudroyées",
            ["BURNINGSTEPPE"] = "Steppes Ardentes",
            ["DARKSHORE"] = "Sombrivage",
            ["DEADWINDPASS"] = "Défilé de Deuillevent",
            ["DESOLACE"] = "Désolace",
            ["DUNMOROGH"] = "Dun Morogh",
            ["DUROTAR"] = "Durotar",
            ["DUSKWOOD"] = "Bois de la Pénombre",
            ["DUSTWALLOW"] = "Marécage d'Aprefange",
            ["EASTERNPLAGUE"] = "Maleterres de l'Est",
            ["ELWYNN"] = "Forêt d'Elwynn",
            ["FELWOOD"] = "Gangrebois",
            ["FERALAS"] = "Féralas",
            ["HILLSBRAD"] = "Contreforts de Hautebrande",
            ["HINTERLANDS"] = "Hinterlands",
            ["LOCHMODAN"] = "Loch Modan",
            ["MOONGLADE"] = "Reflet-de-Lune",
            ["MULGORE"] = "Mulgore",
            ["REDRIDGE"] = "Les Carmines",
            ["SEARINGGORGE"] = "Gorge des Vents Brûlants",
            ["SILITHUS"] = "Silithus",
            ["SILVERPINE"] = "Forêt des Pins Argentés",
            ["SORROWS"] = "Marais des Chagrins",
            ["STONETALON"] = "Les Serres-Rocheuses",
            ["STRANGLETHORN"] = "Vallée de Strangleronce",
            ["TANARIS"] = "Tanaris",
            ["TELDRASSIL"] = "Teldrassil",
            ["TIRISFAL"] = "Clairières de Tirisfal",
            ["UNGOROCRATER"] = "Cratère d'Un'Goro",
            ["WESTERNPLAGUE"] = "Maleterres de l'Ouest",
            ["WESTFALL"] = "Marches de l'Ouest",
            ["WETLANDS"] = "Les Paluns",
            ["WINTERSPRING"] = "Berceau-de-l'Hiver",
            ["BLACKSTONEISLAND"] = "L'Île de la Pierre Noire",
            ["GILLIJIM"] = "L'Île de Gillijim",
            ["GILNEAS"] = "Gilnéas",
            ["HYJAL"] = "Hyjal",
            ["LAPIDIS"] = "L'Île Lapis",
            ["SCARLETENCLAVE"] = "L'Enclave Écalarte",
            ["TELABIM"] = "Tel'Abim",
            ["THALASSIANHIGHLANDS"] = "Hautes-Terres Thalassiennes",
            ["GRIMREACHES"] = "Biefs Sinistres",
            ["NORTHWIND"] = "Norvent",
            ["BALOR"] = "Balor",
            ["DARNASSUS"] = "Darnassus",
            ["IRONFORGE"] = "Forgefer",
            ["ORGRIMMAR"] = "Orgrimmar",
            ["STORMWIND"] = "Hurlevent",
            ["THUNDERBLUFF"] = "Pitons-du-Tonnerre",
            ["UNDERCITY"] = "Fossoyeuse",
            ["ALAHTHALAS"] = "Alah'Thalas",
            ["RUINSOFZULRASAZ"] = "Ruines de Zul'rasaz",
            ["TIRISFALUPLANDS"] = "Hautes-Terres de Tirisfal",
            ["SLICKWICKOILRIG"] = "Plateforme de Nappebourg",
            ["RUGFORDSMOUNTAINREST"] = "Mont-Repos de Rugford",
            ["EARTHENRING"] = "Anneau de Terre",
            ["INSTANCESTEXT"] = "Instances :",
            ["BLACKFATHOMDEEPS"] = "Profondeurs de Brassenoire",
            ["BLACKROCKDEPTH"] = "Profondeurs de Rochenoire",
            ["BLACKROCKSPIRE"] = "Pic de Rochenoire",
            ["DEADMINES"] = "Mortemines",
            ["DIREMAUL"] = "Haches-Tripes",
            ["GNOMEREGAN"] = "Gnomeregan",
            ["MARAUDON"] = "Maraudon",
            ["RAGEFIRECHASM"] = "Gouffre de Ragefeu",
            ["RAZORFENDOWNS"] = "Souilles de Tranchebauge",
            ["RAZORFENKRAUL"] = "Kraal de Tranchebauge",
            ["SCARLETMONASTERY"] = "Monastère Écarlate",
            ["SCHOLOMANCE"] = "Scholomance",
            ["SHADOWFANGKEEP"] = "Donjon d'Ombrecroc",
            ["STOCKADES"] = "La Prison",
            ["STRATHOLME"] = "Stratholme",
            ["SUNKENTEMPLE"] = "Temple d'Atal'Hakkar",
            ["ULDAMAN"] = "Uldaman",
            ["WAILINGCAVERNS"] = "Cavernes des Lamentations",
            ["ZULFARRAK"] = "Zul'Farrak",
            ["COTBLACKMORASS"] = "Grottes du Temps : Le Noir Marécage",
            ["CRESCENTGROVE"] = "Le Bosquet Croissant",
            ["GILNEASCITY"] = "La Citée Gilnéas",
            ["HATEFORGEQUARRY"] = "Carrière de Forgehaine",
            ["KARAZHANCRYPT"] = "La Crypte de Karazhan",
            ["STORMWINDVAULT"] = "Chambre Forte d'Hurlevent",
            ["STORMWROUGHTRUINS"] = "Ruines Forgétempête",
            ["DRAGONMAWRETREAT"] = "Repli de Dragonmaw",
            ["RAIDSTEXT"] = "Raids :",
            ["NAXXRAMAS"] = "Naxxramas",
            ["ONYXIASLAIR"] = "Repaire d'Onyxia",
            ["RUINSAHNQIRAJ"] = "Ruines d'Ahn'Qiraj",
            ["TEMPLEAHNQIRAJ"] = "Temple d'Ahn'Qiraj",
            ["ZULGURUB"] = "Zul'Gurub",
            ["EMERALDSANCTUM"] = "Sanctum d'Émeraude",
            ["LOWERKARAZHANHALLS"] = "Les Salles de Karazhan Inférieures",
            ["LEVELS"] = "Niveaux %d - %d",
            ["FLEVEL"] = "Niveau de Pêche %d",
        },
        ptBR = {
            ["ALLIANCE"] = "Aliança",
            ["HORDE"] = "Horda",
            ["CONTESTED"] = "Zona contestada",
            ["FRIENDLY"] = "Amigável",
            ["HOSTILE"] = "Hostil",
            ["1KNEEDLES"] = "As Mil Agulhas",
            ["ALTERAC"] = "Montanhas de Alterac",
            ["ARATHI"] = "Planalto Arathi",
            ["ASHENVALE"] = "Vale das Cinzas",
            ["AZSHARA"] = "Azshara",
            ["BADLANDS"] = "Ermos",
            ["BARRENS"] = "Os Barrens",
            ["BLASTEDLANDS"] = "Terras Devastadas",
            ["BURNINGSTEPPE"] = "Estepes Ardentes",
            ["DARKSHORE"] = "Costa Negra",
            ["DEADWINDPASS"] = "Desfiladeiro da Morte",
            ["DESOLACE"] = "Desolação",
            ["DUNMOROGH"] = "Dun Morogh",
            ["DUROTAR"] = "Durotar",
            ["DUSKWOOD"] = "Floresta do Crepúsculo",
            ["DUSTWALLOW"] = "Pântano Vadeante",
            ["EASTERNPLAGUE"] = "Terras Pestilentas Orientais",
            ["ELWYNN"] = "Floresta de Elwynn",
            ["FELWOOD"] = "Selva Maleva",
            ["FERALAS"] = "Feralas",
            ["HILLSBRAD"] = "Contrafortes de Eira dos Montes",
            ["HINTERLANDS"] = "As Terras Interiores",
            ["LOCHMODAN"] = "Loch Modan",
            ["MOONGLADE"] = "Moonglade",
            ["MULGORE"] = "Mulgore",
            ["REDRIDGE"] = "Montanhas Redridge",
            ["SEARINGGORGE"] = "Desfiladeiro Searing",
            ["SILITHUS"] = "Silithus",
            ["SILVERPINE"] = "Floresta Silverpine",
            ["SORROWS"] = "Pantano das Tristezas",
            ["STONETALON"] = "Montanhas Stonetalon",
            ["STRANGLETHORN"] = "Vale Stranglethorn",
            ["TANARIS"] = "Tanaris",
            ["TELDRASSIL"] = "Teldrassil",
            ["TIRISFAL"] = "Os Bosques de Tirisfal",
            ["UNGOROCRATER"] = "Cratera Un'Goro",
            ["WESTERNPLAGUE"] = "Plaguelands Ocidentais",
            ["WESTFALL"] = "Westfall",
            ["WETLANDS"] = "Pântanos",
            ["WINTERSPRING"] = "Hibérnia",
            ["BLACKSTONEISLAND"] = "Ilha Negrito",
            ["GILLIJIM"] = "Ilha de Gillijim",
            ["GILNEAS"] = "Gilneas",
            ["HYJAL"] = "Hyjal",
            ["LAPIDIS"] = "Isla Lapidis",
            ["SCARLETENCLAVE"] = "Enclave Scarlet",
            ["TELABIM"] = "Tel'Abim",
            ["THALASSIANHIGHLANDS"] = "Terras Altas Thalassianas",
            ["GRIMREACHES"] = "Recônditos Sombrios",
            ["NORTHWIND"] = "Vento Norte",
            ["BALOR"] = "Balor",
            ["DARNASSUS"] = "Darnassus",
            ["IRONFORGE"] = "Altaforja",
            ["ORGRIMMAR"] = "Orgrimmmar",
            ["STORMWIND"] = "Cidade Stormwind",
            ["THUNDERBLUFF"] = "Thunder Bluff",
            ["UNDERCITY"] = "Cidade Subterrânea",
            ["ALAHTHALAS"] = "Alah'Thalas",
            ["RUINSOFZULRASAZ"] = "Ruins of Zul'rasaz",
            ["TIRISFALUPLANDS"] = "Tirisfal Uplands",
            ["SLICKWICKOILRIG"] = "Slickwick Oil Rig",
            ["RUGFORDSMOUNTAINREST"] = "Rugford's Mountain Rest",
            ["EARTHENRING"] = "Earthen Ring",
            ["INSTANCESTEXT"] = "Masmorras:",
            ["BLACKFATHOMDEEPS"] = "Blackfathom Deeps",
            ["BLACKROCKDEPTH"] = "Blackrock Depths",
            ["BLACKROCKSPIRE"] = "Blackrock Spire",
            ["DEADMINES"] = "Deadmines",
            ["DIREMAUL"] = "Dire Maul",
            ["GNOMEREGAN"] = "Gnomeregan",
            ["MARAUDON"] = "Maraudon",
            ["RAGEFIRECHASM"] = "Ragefire Chasm",
            ["RAZORFENDOWNS"] = "Razorfen Downs",
            ["RAZORFENKRAUL"] = "Razorfen Kraul",
            ["SCARLETMONASTERY"] = "The Scarlet Monastery",
            ["SCHOLOMANCE"] = "Scholomance",
            ["SHADOWFANGKEEP"] = "Shadowfang Keep",
            ["STOCKADES"] = "The Stockades",
            ["STRATHOLME"] = "Stratholme",
            ["SUNKENTEMPLE"] = "The Sunken Temple",
            ["ULDAMAN"] = "Uldaman",
            ["WAILINGCAVERNS"] = "Wailing Caverns",
            ["ZULFARRAK"] = "Zul'Farrak",
            ["COTBLACKMORASS"] = "Caverns of Time: The Black Morass",
            ["CRESCENTGROVE"] = "The Crescent Grove",
            ["GILNEASCITY"] = "Gilneas City",
            ["HATEFORGEQUARRY"] = "Hateforge Quarry",
            ["KARAZHANCRYPT"] = "Karazhan Crypt",
            ["STORMWINDVAULT"] = "Stormwind Vault",
            ["STORMWROUGHTRUINS"] = "Stormwrought Ruins",
            ["DRAGONMAWRETREAT"] = "Dragonmaw Retreat",
            ["RAIDSTEXT"] = "Raides:",
            ["NAXXRAMAS"] = "Naxxramas",
            ["ONYXIASLAIR"] = "Onyxia's Lair",
            ["RUINSAHNQIRAJ"] = "Ruins of Ahn'Qiraj",
            ["TEMPLEAHNQIRAJ"] = "Temple of Ahn'Qiraj",
            ["ZULGURUB"] = "Zul'Gurub",
            ["EMERALDSANCTUM"] = "Emerald Sanctum",
            ["LOWERKARAZHANHALLS"] = "Lower Karazhan Halls",
            ["LEVELS"] = "Níveis %d - %d",
            ["FLEVEL"] = "Nível de pesca %d",
        },
        zhCN = {
            ["ALLIANCE"] = "联盟",
            ["HORDE"] = "部落",
            ["CONTESTED"] = "争夺区域",
            ["FRIENDLY"] = "友好",
            ["HOSTILE"] = "敌对",
            ["1KNEEDLES"] = "千针石林",
            ["ALTERAC"] = "奥特兰克山脉",
            ["ARATHI"] = "阿拉希高地",
            ["ASHENVALE"] = "灰谷",
            ["AZSHARA"] = "艾萨拉",
            ["BADLANDS"] = "荒芜之地",
            ["BARRENS"] = "贫瘠之地",
            ["BLASTEDLANDS"] = "诅咒之地",
            ["BURNINGSTEPPE"] = "燃烧平原",
            ["DARKSHORE"] = "黑海岸",
            ["DEADWINDPASS"] = "逆风小径",
            ["DESOLACE"] = "凄凉之地",
            ["DUNMOROGH"] = "丹莫罗",
            ["DUROTAR"] = "杜隆塔尔",
            ["DUSKWOOD"] = "暮色森林",
            ["DUSTWALLOW"] = "尘泥沼泽",
            ["EASTERNPLAGUE"] = "东瘟疫之地",
            ["ELWYNN"] = "艾尔文森林",
            ["FELWOOD"] = "费伍德森林",
            ["FERALAS"] = "菲拉斯",
            ["HILLSBRAD"] = "希尔斯布莱德丘陵",
            ["HINTERLANDS"] = "辛特兰",
            ["LOCHMODAN"] = "洛克莫丹",
            ["MOONGLADE"] = "月光林地",
            ["MULGORE"] = "莫高雷",
            ["REDRIDGE"] = "赤脊山",
            ["SEARINGGORGE"] = "灼热峡谷",
            ["SILITHUS"] = "希利苏斯",
            ["SILVERPINE"] = "银松森林",
            ["SORROWS"] = "悲伤沼泽",
            ["STONETALON"] = "石爪山脉",
            ["STRANGLETHORN"] = "荆棘谷",
            ["TANARIS"] = "塔纳利斯",
            ["TELDRASSIL"] = "泰达希尔",
            ["TIRISFAL"] = "提瑞斯法林地",
            ["UNGOROCRATER"] = "安戈洛环形山",
            ["WESTERNPLAGUE"] = "西瘟疫之地",
            ["WESTFALL"] = "西部荒野",
            ["WETLANDS"] = "湿地",
            ["WINTERSPRING"] = "冬泉谷",
            ["BLACKSTONEISLAND"] = "黑石岛",
            ["GILLIJIM"] = "吉利吉姆之岛",
            ["GILNEAS"] = "吉尔尼斯",
            ["HYJAL"] = "海加尔山",
            ["LAPIDIS"] = "拉匹迪斯之岛",
            ["SCARLETENCLAVE"] = "东瘟疫之地：血色领地",
            ["TELABIM"] = "泰拉比姆",
            ["THALASSIANHIGHLANDS"] = "阿尔萨拉斯",
            ["GRIMREACHES"] = "冷酷海岸",
            ["NORTHWIND"] = "北风领",
            ["BALOR"] = "巴洛",
            ["DARNASSUS"] = "达纳苏斯",
            ["IRONFORGE"] = "铁炉堡",
            ["ORGRIMMAR"] = "奥格瑞玛",
            ["STORMWIND"] = "暴风城",
            ["THUNDERBLUFF"] = "雷霆崖",
            ["UNDERCITY"] = "幽暗城",
            ["ALAHTHALAS"] = "萨拉斯高地",
            ["RUINSOFZULRASAZ"] = "Ruins of Zul'rasaz",
            ["TIRISFALUPLANDS"] = "Tirisfal Uplands",
            ["SLICKWICKOILRIG"] = "Slickwick Oil Rig",
            ["RUGFORDSMOUNTAINREST"] = "Rugford's Mountain Rest",
            ["EARTHENRING"] = "Earthen Ring",
            ["INSTANCESTEXT"] = "地下城：",
            ["BLACKFATHOMDEEPS"] = "黑暗深渊",
            ["BLACKROCKDEPTH"] = "黑石深渊",
            ["BLACKROCKSPIRE"] = "黑石塔",
            ["DEADMINES"] = "死亡矿井",
            ["DIREMAUL"] = "厄运之槌",
            ["GNOMEREGAN"] = "诺莫瑞根",
            ["MARAUDON"] = "玛拉顿",
            ["RAGEFIRECHASM"] = "怒焰裂谷",
            ["RAZORFENDOWNS"] = "Razorfen Downs",
            ["RAZORFENKRAUL"] = "剃刀高地",
            ["SCARLETMONASTERY"] = "血色修道院",
            ["SCHOLOMANCE"] = "通灵学院",
            ["SHADOWFANGKEEP"] = "影牙城堡",
            ["STOCKADES"] = "监狱",
            ["STRATHOLME"] = "斯坦索姆",
            ["SUNKENTEMPLE"] = "The Sunken Temple",
            ["ULDAMAN"] = "奥达曼",
            ["WAILINGCAVERNS"] = "哀嚎洞穴",
            ["ZULFARRAK"] = "祖尔法拉克",
            ["COTBLACKMORASS"] = "Caverns of Time: The Black Morass",
            ["CRESCENTGROVE"] = "The Crescent Grove",
            ["GILNEASCITY"] = "Gilneas City",
            ["HATEFORGEQUARRY"] = "Hateforge Quarry",
            ["KARAZHANCRYPT"] = "Karazhan Crypt",
            ["STORMWINDVAULT"] = "Stormwind Vault",
            ["STORMWROUGHTRUINS"] = "Stormwrought Ruins",
            ["DRAGONMAWRETREAT"] = "Dragonmaw Retreat",
            ["RAIDSTEXT"] = "团队副本：",
            ["NAXXRAMAS"] = "納克薩瑪斯",
            ["ONYXIASLAIR"] = "奧妮克希亞的巢穴",
            ["RUINSAHNQIRAJ"] = "安其拉廢墟",
            ["TEMPLEAHNQIRAJ"] = "安其拉神廟",
            ["ZULGURUB"] = "祖爾格拉布",
            ["EMERALDSANCTUM"] = "Emerald Sanctum",
            ["LOWERKARAZHANHALLS"] = "Lower Karazhan Halls",
            ["LEVELS"] = "等级 %d - %d",
            ["FLEVEL"] = "钓鱼等级 %d",
        },
    }

    -- { zone, min, max, side }  side: A = Alliance, H = Horde, C = Contested
    local RANGES = {
        { "ELWYNN", 1, 10, "A" }, { "DUNMOROGH", 1, 10, "A" }, { "TIRISFAL", 1, 10, "H" },
        { "LOCHMODAN", 10, 20, "A" }, { "SILVERPINE", 10, 20, "H" }, { "WESTFALL", 10, 20, "A" },
        { "REDRIDGE", 15, 25, "C" }, { "DUSKWOOD", 18, 30, "C" }, { "HILLSBRAD", 20, 30, "C" },
        { "WETLANDS", 20, 30, "C" }, { "ALTERAC", 30, 40, "C" }, { "ARATHI", 30, 40, "C" },
        { "STRANGLETHORN", 30, 45, "C" }, { "BADLANDS", 35, 45, "C" }, { "SORROWS", 35, 45, "C" },
        { "HINTERLANDS", 40, 50, "C" }, { "SEARINGGORGE", 43, 50, "C" }, { "BLASTEDLANDS", 45, 55, "C" },
        { "BURNINGSTEPPE", 50, 58, "C" }, { "WESTERNPLAGUE", 51, 58, "C" }, { "EASTERNPLAGUE", 53, 60, "C" },
        { "DEADWINDPASS", 55, 60, "C" },

        { "DUROTAR", 1, 10, "H" }, { "MULGORE", 1, 10, "H" }, { "DARKSHORE", 10, 20, "A" },
        { "BARRENS", 10, 25, "H" }, { "STONETALON", 15, 27, "C" }, { "ASHENVALE", 18, 30, "C" },
        { "1KNEEDLES", 25, 35, "C" }, { "DESOLACE", 30, 40, "C" }, { "DUSTWALLOW", 35, 45, "C" },
        { "FERALAS", 40, 50, "C" }, { "TANARIS", 40, 50, "C" }, { "AZSHARA", 45, 55, "C" },
        { "FELWOOD", 48, 55, "C" }, { "UNGOROCRATER", 48, 55, "C" }, { "SILITHUS", 55, 60, "C" },
        { "WINTERSPRING", 55, 60, "C" },

        { "MOONGLADE", 1, 60, "C" }, { "TELDRASSIL", 1, 10, "A" },

        -- Turtle WoW zones
        { "THALASSIANHIGHLANDS", 1, 10, "A" }, { "BLACKSTONEISLAND", 1, 10, "H" },
        { "GILNEAS", 39, 46, "C" }, { "GILLIJIM", 48, 53, "C" }, { "LAPIDIS", 48, 53, "C" },
        { "TELABIM", 54, 60, "C" }, { "SCARLETENCLAVE", 55, 60, "C" }, { "HYJAL", 58, 60, "C" },
        -- patch 1.18
        { "GRIMREACHES", 33, 38, "C" }, { "NORTHWIND", 28, 34, "C" }, { "BALOR", 29, 34, "C" },
    }

    -- Minimum fishing skill per zone.
    local FISHING = {
        ELWYNN = 25, DUNMOROGH = 25, TIRISFAL = 25, LOCHMODAN = 75, SILVERPINE = 75,
        WESTFALL = 75, REDRIDGE = 150, DUSKWOOD = 150, HILLSBRAD = 150, WETLANDS = 150,
        ALTERAC = 225, ARATHI = 225, STRANGLETHORN = 225, BADLANDS = 35, SORROWS = 225,
        HINTERLANDS = 300, WESTERNPLAGUE = 300,
        DUROTAR = 25, MULGORE = 25, DARKSHORE = 75, BARRENS = 75, STONETALON = 150,
        ASHENVALE = 150, ["1KNEEDLES"] = 225, DESOLACE = 225, DUSTWALLOW = 225, FERALAS = 300,
        TANARIS = 300, AZSHARA = 300, FELWOOD = 300, UNGOROCRATER = 300,
        MOONGLADE = 300, TELDRASSIL = 25,
    }

    -- zone = { name, levels, name, levels, ... }
    local INSTANCES = {
        WESTFALL = { "DEADMINES", " (17-26)" },
        BARRENS = { "WAILINGCAVERNS", " (17-24)", "RAZORFENKRAUL", " (25-30)", "RAZORFENDOWNS", " (33-45)" },
        SILVERPINE = { "SHADOWFANGKEEP", " (22-30)" },
        DUNMOROGH = { "GNOMEREGAN", " (29-38)" },
        TIRISFAL = { "SCARLETMONASTERY", " (34-45)" },
        BADLANDS = { "ULDAMAN", " (35-47)" },
        DESOLACE = { "MARAUDON", " (46-55)" },
        SORROWS = { "SUNKENTEMPLE", " (45-55)" },
        SEARINGGORGE = { "BLACKROCKDEPTH", " (52-60)", "BLACKROCKSPIRE", " (58-60)" },
        EASTERNPLAGUE = { "STRATHOLME", " (58-60)" },
        FERALAS = { "DIREMAUL", " (55-60)" },
        WESTERNPLAGUE = { "SCHOLOMANCE", " (57-60)" },
        DUROTAR = { "RAGEFIRECHASM", " (13-18)" },
        -- Turtle WoW dungeons
        ASHENVALE = { "BLACKFATHOMDEEPS", " (24-32)", "CRESCENTGROVE", " (32-38)" },
        GILNEAS = { "GILNEASCITY", " (43-49)" },
        BURNINGSTEPPE = { "HATEFORGEQUARRY", " (52-60)", "BLACKROCKDEPTH", " (52-60)", "BLACKROCKSPIRE", " (58-60)" },
        DEADWINDPASS = { "KARAZHANCRYPT", " (58 - 60)" },
        ELWYNN = { "STOCKADES", " (24-32)", "STORMWINDVAULT", " (60+)" },
        TANARIS = { "ZULFARRAK", " (44-54)", "COTBLACKMORASS", " (60+)" },
        -- patch 1.18
        BALOR = { "STORMWROUGHTRUINS", " (35-41)" },
        WETLANDS = { "DRAGONMAWRETREAT", " (27-33)" },
    }

    local RAIDS = {
        EASTERNPLAGUE = { "NAXXRAMAS", " (60+)" },
        DUSTWALLOW = { "ONYXIASLAIR", " (60+)" },
        SILITHUS = { "RUINSAHNQIRAJ", " (60+)", "TEMPLEAHNQIRAJ", " (60+)" },
        STRANGLETHORN = { "ZULGURUB", " (60+)" },
        -- Turtle WoW raids
        HYJAL = { "EMERALDSANCTUM", " (60+)" },
        DEADWINDPASS = { "LOWERKARAZHANHALLS", " (60+)" },
    }

    -- Cities on the continent map count as their zone.
    local SUBZONES = {
        ORGRIMMAR = "DUROTAR", THUNDERBLUFF = "MULGORE", UNDERCITY = "TIRISFAL",
        IRONFORGE = "DUNMOROGH", STORMWIND = "ELWYNN", DARNASSUS = "TELDRASSIL",
        ALAHTHALAS = "THALASSIANHIGHLANDS",
    }

    local COL_UNKNOWN = { 0.8, 0.8, 0.8 }
    local COL_HOSTILE = { 0.9, 0.2, 0.2 }
    local COL_FRIENDLY = { 0.2, 0.9, 0.2 }
    local COL_CONTESTED = { 0.8, 0.6, 0.4 }
    local COL_NAME = { 1, 1, 1 }
    local COL_LEVELS = { 0.8, 0.6, 0.0 }

    local S = {}
    local byName = {}
    local rangeOf = {}
    local st = { installed = false, blocked = nil, noticed = false, zone = nil, area = nil, tip = nil }

    local function buildNames()
        local base = LOC.enUS
        local cur = LOC[GetLocale and GetLocale() or "enUS"] or base
        local k, v
        for k, v in pairs(base) do
            S[k] = cur[k] or v
        end
        local i, r
        for i = 1, table.getn(RANGES) do
            r = RANGES[i]
            rangeOf[r[1]] = r
            byName[S[r[1]]] = r[1]
        end
        for k, v in pairs(SUBZONES) do
            byName[S[k]] = v
        end
    end

    local function cfg()
        if IchaUI_WorldMap_Get then return IchaUI_WorldMap_Get() end
        if type(IchaUIDB) ~= "table" then IchaUIDB = {} end
        if type(IchaUIDB.worldmap) ~= "table" then IchaUIDB.worldmap = {} end
        return IchaUIDB.worldmap
    end

    local function opt(key, default)
        local v = cfg()[key]
        if v == nil then return default end
        return v and true or false
    end

    local function levelRangeLoaded()
        if IsAddOnLoaded and IsAddOnLoaded("LevelRange-Turtle") then return true end
        if LevelRange_WorldMapButton_OnUpdate or LevelRangeTooltip then return true end
        return false
    end

    local function chat(msg)
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffedc75aIchaUI|r: " .. msg)
        end
    end

    -- Parented to UIParent so the map's opacity never fades it; the scale
    -- follows the map so it still reads at the map's size.
    local function liftTip(t)
        if t:GetParent() ~= UIParent then t:SetParent(UIParent) end
        t:SetFrameStrata("TOOLTIP")
        local ms = WorldMapFrame:GetEffectiveScale() or 0
        local us = UIParent:GetEffectiveScale() or 0
        if ms > 0 and us > 0 then t:SetScale(ms / us) end
        t:SetAlpha(1)
    end

    -- Fixed 0.9 panel: the theme fill opacity must not wash the text out.
    local function skinTip(t)
        local r, g, b = 0.07, 0.07, 0.08
        if IchaUI_Fill then r, g, b = IchaUI_Fill() end
        if r > 0.2 or g > 0.2 or b > 0.2 then r, g, b = 0.07, 0.07, 0.08 end
        t:SetBackdropColor(r, g, b, 0.9)
        local br, bg, bb = 1, 1, 1
        if IchaUI_Gold then br, bg, bb = IchaUI_Gold() end
        t:SetBackdropBorderColor(br, bg, bb, 1)
    end

    local function ensureTip()
        if st.tip then return st.tip end
        local t = CreateFrame("GameTooltip", "IchaUIMapLevelTip", UIParent, "GameTooltipTemplate")
        t:SetFrameStrata("TOOLTIP")
        t:Hide()
        st.tip = t
        return t
    end

    local function placeTip(t)
        t:ClearAllPoints()
        -- A zoomed detail frame's corner can be off view; use the clip frame.
        local host = (IchaUI_WorldMap_Viewport and IchaUI_WorldMap_Viewport())
            or WorldMapFrameScrollFrame or WorldMapDetailFrame
        if FlightMapFrame then
            t:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
        else
            t:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
        end
    end

    local function addPairs(t, list)
        local i = 1
        while list[i] do
            t:AddDoubleLine("|cffcfcfcf" .. (S[list[i]] or list[i]) .. "|r", "|cffcfcfcf" .. (list[i + 1] or "") .. "|r")
            i = i + 2
        end
    end

    -- Fills the tooltip for a zone key. Returns true if it has level info.
    function IchaUI_MapLevels_Fill(t, key)
        local r = key and rangeOf[key]
        if not r then return false end
        local _, faction = UnitFactionGroup("player")
        local sideText, sideCol
        if r[4] == "C" then
            sideText, sideCol = S.CONTESTED, COL_CONTESTED
        else
            local sideName = S.ALLIANCE
            if r[4] == "H" then sideName = S.HORDE end
            if faction == sideName then
                sideText, sideCol = S.FRIENDLY, COL_FRIENDLY
            else
                sideText, sideCol = S.HOSTILE, COL_HOSTILE
            end
        end
        t:SetText(S[key] or key, COL_NAME[1], COL_NAME[2], COL_NAME[3])
        t:AddLine(string.format(S.LEVELS, r[2], r[3]), COL_LEVELS[1], COL_LEVELS[2], COL_LEVELS[3])
        if opt("levelFish", false) and FISHING[key] then
            t:AddLine(string.format(S.FLEVEL, FISHING[key]), COL_LEVELS[1], COL_LEVELS[2], COL_LEVELS[3])
        end
        if opt("levelPvP", true) and sideText then
            t:AddLine(sideText, sideCol[1], sideCol[2], sideCol[3])
        end
        if opt("levelInst", true) and INSTANCES[key] then
            t:AddLine(" ")
            t:AddLine(S.INSTANCESTEXT)
            addPairs(t, INSTANCES[key])
        end
        if opt("levelRaids", true) and RAIDS[key] then
            t:AddLine(" ")
            t:AddLine(S.RAIDSTEXT)
            addPairs(t, RAIDS[key])
        end
        return true
    end

    -- Zone key for a continent-map area name, or nil.
    function IchaUI_MapLevels_ZoneKey(areaName)
        local _, _, trimmed = string.find(areaName or "", "^%s*(.-)%s*$")
        if not trimmed or trimmed == "" then return nil end
        return byName[trimmed]
    end

    local function show(key)
        local t = ensureTip()
        if not key or not opt("levels", true) or st.blocked then
            t:Hide()
            return
        end
        t:SetOwner(WorldMapButton, "ANCHOR_LEFT")
        if IchaUI_MapLevels_Fill(t, key) then
            liftTip(t)
            t:Show()
            skinTip(t)
            placeTip(t)
        else
            t:Hide()
        end
    end

    local function onUpdate()
        local area = WorldMapFrame.areaName or ""
        local zoneNum = GetCurrentMapZone()
        if zoneNum == st.zone and area == st.area then return end
        st.zone, st.area = zoneNum, area
        if zoneNum == 0 then
            show(IchaUI_MapLevels_ZoneKey(area))
        else
            show(nil)
        end
    end

    function IchaUI_MapLevels_Blocked()
        return st.blocked and true or false
    end

    -- Drops the cached hover so the next map update redraws with new settings.
    function IchaUI_MapLevels_Refresh()
        st.zone, st.area = nil, nil
        if st.tip and (st.blocked or not opt("levels", true)) then st.tip:Hide() end
    end

    -- LevelRange ships its tooltip with a fully transparent backdrop and as a
    -- map child, so it fades with the map. Give it the same readable panel.
    local function fixLevelRangeTip()
        local t = LevelRangeTooltip
        if not t or t._ichaLifted or not t.SetBackdropColor then return end
        t._ichaLifted = true
        liftTip(t)
        local prev = t:GetScript("OnShow")
        t:SetScript("OnShow", function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            if prev then prev(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
            liftTip(t)
            skinTip(t)
        end)
    end

    local function hideTips()
        if st.tip then st.tip:Hide() end
        if LevelRangeTooltip and LevelRangeTooltip._ichaLifted then LevelRangeTooltip:Hide() end
    end

    local function install()
        if st.installed or not WorldMapButton or not WorldMapFrame then return end
        st.installed = true
        local prevHide = WorldMapFrame:GetScript("OnHide")
        WorldMapFrame:SetScript("OnHide", function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            if prevHide then prevHide(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
            hideTips()
        end)
        if levelRangeLoaded() then
            fixLevelRangeTip()
            st.blocked = true
            if opt("levels", true) and not st.noticed then
                st.noticed = true
                chat("LevelRange is loaded, so IchaUI's map level ranges stay off. "
                    .. "Disable |cffffffffLevelRange|r in the AddOns list to use IchaUI's.")
            end
            return
        end
        st.blocked = false
        ensureTip()
        local prev = WorldMapButton:GetScript("OnUpdate")
        WorldMapButton:SetScript("OnUpdate", function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            if prev then prev(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
            onUpdate()
        end)
    end

    buildNames()

    local boot = CreateFrame("Frame", "IchaUIMapLevelsBoot")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:SetScript("OnEvent", function()
        this:UnregisterAllEvents()
        install()
        if IchaUI_WorldMap_OptRefresh then IchaUI_WorldMap_OptRefresh() end
    end)
end

installIchaUIMapLevels()
