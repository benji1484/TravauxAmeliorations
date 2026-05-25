# Notes d'analyse du modele Power BI

Date d'analyse : 2026-05-25

## Perimetre

- Dossier analyse : `C:\Users\lemoald\Documents\Travaux amelioration`
- Modele parent : `Pilotage MensuelV3 - Parent/Pilotage Mensuelv3.SemanticModel`
- Rapport parent : `Pilotage MensuelV3 - Parent/Pilotage Mensuelv3.Report`
- Fichier principal des mesures : `Pilotage MensuelV3 - Parent/Pilotage Mensuelv3.SemanticModel/definition/tables/Mesure.tmdl`

## Synthese du modele parent

- 26 tables referencees dans le modele parent.
- 495 colonnes.
- 392 mesures, presque toutes centralisees dans la table `Mesure`.
- 63 relations.
- 26 relations ont encore un nom `AutoDetected_*`.
- 5 relations sont inactives.
- 60 mesures seulement ont un `displayFolder`, toutes dans `Dimension Temps`.
- 0 description de mesure trouvee dans `Mesure.tmdl`.
- 0 mesure masquee trouvee dans `Mesure.tmdl`.

## Raccordement des rapports au modele

La majorite des rapports pointe vers le semantic model publie `Pilotage Mensuelv3`, mais pas tous.

- 16 rapports pointent vers le modele parent, soit par chemin local, soit par `semanticmodelid=be09a186-af88-4abe-bfe6-3a76507d8d3f`.
- 3 rapports ne pointent pas directement vers le modele parent :
  - `Activite de developpement et rehab` utilise un semantic model local.
  - `Vacance financiere commerce` utilise un semantic model local.
  - `Tdb DDC` pointe vers `semanticmodelid=fec2e7fa-cd1e-4c01-b816-d3757547a8dd`.

Point d'attention : si on renomme ou supprime une mesure dans le modele parent, il faudra verifier les rapports connectes au modele parent publie, mais aussi clarifier le statut des trois rapports qui utilisent un autre semantic model.

## Points d'amelioration prioritaires

1. Classer les mesures par domaines metier

Les 392 mesures sont concentrees dans une table technique `Mesure`. Une classification par dossiers rendrait le modele beaucoup plus lisible :

- Encaissement
- Dette / impayes
- Vacance financiere
- Vacance physique
- Patrimoine / stock
- Flux d'occupation
- Peuplement / salaries
- Assurances
- Objectifs / interessement
- Couleurs / narratifs / mesures techniques
- Mesures a controler / obsoletes

2. Normaliser les noms de mesures

Les noms melangent plusieurs conventions : francais, anglais, abbreviations, underscores, accents, majuscules/minuscules, suffixes `YTD`, `M`, `M-1`, `N-1`, `LY`, `new`, `alt`, `graph`, `test`.

Exemples a reprendre en priorite :

- `Mesure`, `Mesure 2`, `Mesure 3`, `Mesure 4`, `Mesure 5`, `Mesure 6`, `Mesure 7`
- `test`
- `CroissanceSoldem_CA_Operation_YTD_test`
- `Mobilite YTD new`
- `Livraisons cumulees alt`
- `Entrées salaries YTD graph`

3. Ajouter des descriptions

Aucune description de mesure n'a ete detectee. C'est un gros levier d'accessibilite pour les utilisateurs et les futurs mainteneurs. Les mesures exposees devraient au minimum documenter :

- definition metier ;
- granularite attendue ;
- filtre implicite important ;
- unite ou format ;
- difference entre mensuel, YTD, N-1, M-1.

4. Masquer les mesures techniques et intermediaires

Aucune mesure masquee n'a ete detectee dans la table `Mesure`. Les mesures intermediaires qui servent uniquement a calculer des indicateurs visibles devraient etre masquees apres validation.

5. Nettoyer les mesures obsoletes ou temporaires

Plusieurs mesures ressemblent a des essais, des duplicats ou des indicateurs historiques. Elles sont de bonnes candidates pour une revue rapide :

- mesures nommees `Mesure*` ;
- mesures `test`, `*_test`, `new`, `alt`, `graph` ;
- mesures avec annee fixe : `Logements 2023`, `Entrées 2024`, `Sorties 2024`, `Mobilite 2024`, `Ventes 2024` ;
- mesures de satisfaction ou objectifs en dur : `Satisfaction globale`, `Satisfaction reclamation`, `Objectif encaissement`, `Objectif annuel vac fi`.

6. Revoir les objectifs et annees fixes

Le modele contient `Obj_2024` et plusieurs mesures liees a une annee ou a des objectifs codes en dur. Pour eviter une maintenance annuelle fragile, il faudrait preferer une table d'objectifs parametree par periode, domaine, indicateur et niveau territorial.

7. Consolider les mesures proches

Les familles de mesures autour de la vacance, de la dette et de l'encaissement ont beaucoup de variantes proches. Avant renommage, il faut etablir une nomenclature cible et identifier les mesures qui font reellement doublon.

Exemples de familles a rationaliser :

- `Taux Encaissement`, `Tx Encaissement`, `% Taux Encaissement`, `tx encaissement`
- `Vacance Financiere`, `vacance financière`, `VacanceFinanciere`, `Tx Vac Fi`
- `Dette`, `soldem_ca_operation`, `CroissanceSoldem`

8. Nettoyer les requetes d'erreur

Le modele contient encore des groupes et expressions d'erreur :

- `Erreurs des requetes - 20/11/2025 15:56:26`
- `Erreurs des requetes - 21/11/2025 10:39:35`
- `Erreurs des requetes - 25/05/2026 08:16:37`
- `Erreurs dans Scoring Patrimoine`
- `Erreurs dans Scoring Patrimoine depiv`

Ces elements devraient etre confirmes puis supprimes s'ils ne servent plus.

9. Revoir les relations auto-detectees

26 relations ont encore un nom `AutoDetected_*`. Pour un modele parent partage, il vaut mieux nommer ou au moins valider les relations structurantes, surtout celles qui filtrent les faits principaux.

10. Clarifier le modele temps

Le modele utilise au moins `DateTable` et `PeriodeCal`, avec des mesures basees sur `TOTALYTD`, `SAMEPERIODLASTYEAR`, `DATEADD`, `TODAY()` et des periodes texte. Il faudra clarifier la table calendrier officielle et limiter les calculs dependants de `TODAY()` quand l'analyse doit etre reproductible par periode de reporting.

11. Ameliorer l'accessibilite utilisateur

Pour rendre le modele plus exploitable par les utilisateurs :

- cacher les colonnes techniques de type code, cle, periode brute, colonnes intermediaires ;
- exposer des libelles metier comprehensibles ;
- harmoniser les formats numeriques, pourcentages et euros ;
- documenter les mesures visibles ;
- ranger les mesures par dossier ;
- limiter les noms trop techniques issus des tables sources.

## Methode de detection des mesures non utilisees

Analyse statique effectuee dans les fichiers PBIP :

- extraction des 392 mesures du fichier `Mesure.tmdl` ;
- scan des fichiers JSON sous chaque dossier `.Report/definition` ;
- detection des objets `"Measure"` et des `queryRef` de type `Mesure.<nom mesure>` ;
- calcul des dependances DAX entre mesures via les references `[Nom mesure]` ;
- distinction entre mesures utilisees directement dans un rapport et mesures seulement necessaires a une mesure utilisee.

Limites de la methode :

- l'analyse ne remplace pas une ouverture/test dans Power BI Desktop ;
- les usages externes au depot ne sont pas detectes ;
- les usages dynamiques tres specifiques ou certains custom visuals peuvent echapper au scan ;
- les rapports qui ne pointent pas vers le parent peuvent contenir des mesures de meme nom sans utiliser le parent ;
- avant suppression definitive, il est preferable de masquer les mesures candidates, tester les rapports, puis supprimer dans un second commit.

## Resultats sur les 19 rapports du depot

- 241 mesures sont utilisees directement par au moins un rapport du depot.
- 151 mesures ne sont utilisees directement par aucun rapport du depot.
- Parmi ces 151 mesures, 15 sont quand meme des dependances de mesures utilisees.
- 136 mesures sont candidates a suppression conservatrice : elles ne sont pas utilisees directement dans les rapports et ne semblent pas necessaires a une mesure utilisee.

Nombre de mesures du parent detectees par rapport :

| Rapport | Mesures detectees |
|---|---:|
| Activite de developpement et rehab | 11 |
| Analyse par ville | 35 |
| ARMOS - Etude rotation | 2 |
| ARMOS Annuel | 11 |
| ARMOS Annuel 2 | 11 |
| CA - Acceuil | 18 |
| CA - Exploitation du parc | 37 |
| Carte identite groupe | 73 |
| KPI affichage | 14 |
| Pilotage des assurances | 18 |
| Pilotage MensuelV3 - Parent | 131 |
| Preuves Tx Encaissement | 25 |
| Probable - tx d'encaissement mensuels | 1 |
| RALI | 20 |
| Suivi des paiements | 12 |
| Suivi quotidien dette | 21 |
| Tdb DDC | 21 |
| Vacance commerce | 60 |
| Vacance financiere commerce | 31 |

## Resultats limites aux 16 rapports raccordes au modele parent

- 231 mesures sont utilisees directement par les rapports raccordes au parent.
- 161 mesures ne sont utilisees directement par aucun rapport raccorde au parent.
- 15 mesures sont des dependances de mesures utilisees.
- 146 mesures sont candidates a suppression si on raisonne strictement sur le modele parent.

Les 10 mesures supplementaires par rapport a la liste conservatrice globale sont utilisees uniquement dans des rapports qui ne pointent pas vers le modele parent :

- `Vacance commerciale - Commerces & Bureaux`
- `Vacance commerciale YTD - Commerces & Bureaux`
- `Vacance financière - Commerces & Bureaux`
- `Vacance financière YTD - Commerces & Bureaux`
- `Vacance MEL - Commerces & Bureaux`
- `Vacance MEL YTD - Commerces & Bureaux`
- `Vacance stratégique - Commerces & Bureaux`
- `Vacance stratégique YTD - Commerces & Bureaux`
- `Vacance technique - Commerces & Bureaux`
- `Vacance technique YTD - Commerces & Bureaux`

## Mesures non utilisees directement mais a ne pas supprimer seules

Ces 15 mesures ne sont pas placees directement dans un rapport, mais elles sont utilisees par au moins une autre mesure detectee dans un rapport.

| Mesure | Ligne |
|---|---:|
| `# Entrées LOC YTD` | 3570 |
| `# Logements et commerces contractés` | 3895 |
| `% Commerces` | 2830 |
| `€ PP` | 3431 |
| `€ Quittancement logements et commerces M` | 3812 |
| `€ Quittancement logements et commerces YTD` | 3817 |
| `MoisDecembrePrecedent` | 2111 |
| `Quittancement Logements M` | 3611 |
| `TotalVacanceComm_ug` | 1418 |
| `TotalVacanceDemol_ug` | 1562 |
| `TotalVacanceStrat_ug` | 1443 |
| `TotalVacanceTech_ug` | 1467 |
| `TotalVacanceVendu_ug` | 1538 |
| `Vacance Financière Commerce et Logement TCC M` | 3801 |
| `Vacance Stratégique logement` | 1092 |

## Mesures candidates a suppression conservatrice

Ces 136 mesures ne sont pas detectees dans les 19 rapports du depot et ne semblent pas etre des dependances de mesures utilisees.

| Mesure | Ligne |
|---|---:|
| `# CA` | 73 |
| `# CA presents` | 655 |
| `# Livraisons Mensuelles commerces` | 1121 |
| `# Logements contractés` | 2771 |
| `# Logements vacants m-1` | 1996 |
| `# Sorties YTD LY` | 3451 |
| `# UG M1` | 47 |
| `% Entrées Salariés` | 410 |
| `% quittançable TTC` | 2898 |
| `% Tx Vac Comm Fi mensuelle` | 502 |
| `% Tx Vac Strat Fi mensuelle` | 470 |
| `% Tx Vac Tech Fi mensuelle` | 487 |
| `% tximpaye M Operation` | 157 |
| `% txrecouv Hpp M operation` | 97 |
| `% txrecouv Hpp YTD operation` | 137 |
| `% txrecouv M operation` | 82 |
| `% txrecouv YTD operation` | 117 |
| `% Vac strat` | 1297 |
| `% Vacance Financière Commerces M` | 3728 |
| `% Vacance Financière Commerces YTD` | 3723 |
| `% Vacance Financière Commerciale Commerces YTD` | 3713 |
| `% Vacance Financière Stratégique Commerces YTD` | 3718 |
| `% Vacance globale commerces et logements HC YTD` | 3848 |
| `€ Quittancement logements et commerces M HC` | 3826 |
| `€ Quittancement logements et commerces YTD HC` | 3831 |
| `€ Quittancement YTD M-1` | 3890 |
| `€ Total Vacance M UG` | 386 |
| `Absenteisme :` | 1753 |
| `Acquisitions` | 1725 |
| `Affaires économiques sociales et familiales` | 1835 |
| `Affaires traitées` | 1831 |
| `Agréments` | 1785 |
| `Agréments Réhab` | 1839 |
| `Aménagements PMR` | 1773 |
| `Attributions salariées` | 1769 |
| `Autre variation de stock` | 43 |
| `Balance annuelle` | 675 |
| `Compromis :` | 1721 |
| `croissance_soldem_ca_operation_+` | 1254 |
| `CroissanceSoldem_CA_Operation_YTD N-1` | 1234 |
| `CroissanceSoldem_CA_Operation_YTD_test` | 3359 |
| `DAF Financements obtenus` | 1804 |
| `DAF Trésoreries` | 1800 |
| `Dates données GL` | 2083 |
| `DDC Livraisons` | 1777 |
| `Découpage 2` | 2644 |
| `Découpage1` | 2617 |
| `Dette avec PP` | 901 |
| `Dette YTD` | 3442 |
| `DIS dénominateur` | 2724 |
| `DIS indicateur % de loyer / loyer plafond` | 2729 |
| `DIS numérateur` | 2719 |
| `DistinctCount_CodeCA_par_Tranche` | 2102 |
| `Dont CDI :` | 1748 |
| `Encaissement_Alloc_Cumul_Annuel` | 2573 |
| `Entrées 2024` | 1761 |
| `Entrées salariées recalcul` | 1815 |
| `Entrées salariés YTD graph` | 1277 |
| `Entrées YTD LOC` | 1301 |
| `Entrées YTD N-1` | 602 |
| `ETP` | 1743 |
| `Fonds propres` | 1808 |
| `heures d'insertion` | 1788 |
| `Indice de pauvreté` | 3871 |
| `Livraisons cumulées alt` | 1140 |
| `Logements 2023` | 1696 |
| `Logements indécents` | 2698 |
| `Mesure` | 965 |
| `Mesure 2` | 1713 |
| `Mesure 3` | 1969 |
| `Mesure 4` | 2689 |
| `Mesure 5` | 2825 |
| `Mesure 6` | 3998 |
| `Mesure 7` | 4024 |
| `Mises en chantier` | 1782 |
| `Mises en chantier Réhab` | 1740 |
| `Mobilité 2024` | 1765 |
| `MoisDecembre` | 3400 |
| `Moyenne Glissante 12m Vac fi` | 12 |
| `Nb jour vac YTD` | 1590 |
| `Nb NA` | 3122 |
| `Nb PLS` | 3227 |
| `Nombre d'entrée PP` | 659 |
| `Nombre d'entrée PP YTD` | 390 |
| `Objectif annuel vac fi` | 382 |
| `Objectif encaissement` | 960 |
| `Objectif vac fi à date` | 851 |
| `Parcelles` | 3860 |
| `Quitm_ca_calculé` | 2701 |
| `Quitm_CA_Operation_Annuel` | 2520 |
| `Quittancement Commerces` | 3694 |
| `Quittancement Commerces YTD` | 3700 |
| `Quittancement m1` | 3782 |
| `Ratio contrôle` | 1272 |
| `Réhabilitations Livrées` | 1737 |
| `Réservations PSLA :` | 1729 |
| `Salaire injectés` | 1792 |
| `Satisfaction globale` | 954 |
| `Satisfaction réclamation` | 957 |
| `Soldem_ca_operation_+ yc PP_presents` | 1704 |
| `Soldem_ca_operation_+_Absent` | 647 |
| `Soldem_ca_operation_+_LOC` | 373 |
| `Sorties 2024` | 1757 |
| `T1` | 2914 |
| `Taux - 20 jours réclamation 2024` | 1811 |
| `Taux Paiement HPP M` | 2232 |
| `Taux Paiement HPP M-1` | 2246 |
| `Taux Paiement HPP M-12` | 2260 |
| `Taux_Mobilité_YoY_YTD_Dyn` | 866 |
| `test` | 3787 |
| `Total logements` | 1873 |
| `TotalVacanceMEL_ug` | 3335 |
| `Tx dématérialisation` | 3911 |
| `Tx Encaissement HPP Soldes_CA_Operation N-1` | 1178 |
| `Tx Mutation` | 2753 |
| `tx vac fi comm recalcul` | 1321 |
| `Tx Vac Mensuelle` | 679 |
| `Tx Vac Mensuelle TxVacCommm` | 706 |
| `Tx Vac Mensuelle TxVacMELm` | 732 |
| `Tx Vac Mensuelle TxVacStratm` | 758 |
| `Tx Vac Mensuelle TxVacTechm` | 784 |
| `Tx_recouvrement_impayé` | 177 |
| `Vacance Financière Commerce et Logement HC M` | 3836 |
| `Vacance Financière Commerce et Logement HC YTD` | 3842 |
| `Vacance financière commerciale COM` | 3642 |
| `Vacance Financière Commerciale COM YTD` | 3668 |
| `Vacance Financière Stratégique COM` | 3656 |
| `Vacance Financière Stratégique COM YTD` | 3662 |
| `vacance financière totale` | 833 |
| `vacance mensuelle rali` | 1512 |
| `VacanceFinanciereHCYTDRecalcule` | 1656 |
| `VacanceFinanciereYTD` | 1371 |
| `VacanceFinancièreYTD_LastPériode` | 3 |
| `variation dette` | 77 |
| `Ventes` | 1117 |
| `Ventes 2024` | 1718 |

## Proposition de sequence de nettoyage

1. Valider le perimetre des rapports : confirmer si les 3 rapports non raccordes au parent doivent etre rattaches, exclus, ou traites comme modeles independants.
2. Masquer d'abord les 136 candidates au lieu de les supprimer directement.
3. Ouvrir/tester les rapports principaux dans Power BI Desktop.
4. Supprimer par lots metier : mesures de test, annees fixes, objectifs obsoletes, puis doublons.
5. Faire un commit Git par lot, avec possibilite de rollback via `git revert`.
6. Ensuite seulement, lancer le renommage harmonise des mesures conservees.
