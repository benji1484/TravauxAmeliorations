param(
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path ".").Path
$SemanticModelRoot = Join-Path $Root "Pilotage MensuelV3 - Parent\Pilotage Mensuelv3.SemanticModel\definition"
$MeasurePath = Join-Path $SemanticModelRoot "tables\Mesure.tmdl"
$MappingPath = Join-Path $Root "RENOMMAGE_MESURES_POWER_BI.csv"
$ParentSemanticModelId = "be09a186-af88-4abe-bfe6-3a76507d8d3f"

function Read-Utf8 {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Normalize-Spaces {
    param([string]$Text)
    return (($Text -replace "\s+", " ").Trim())
}

function Escape-TmdlName {
    param([string]$Name)
    return $Name.Replace("'", "''")
}

function Escape-JsonString {
    param([string]$Text)
    return $Text.Replace("\", "\\").Replace('"', '\"')
}

function Get-MeasureBlocks {
    param([string]$Text, [string]$FileName = "Mesure.tmdl")

    $matches = [regex]::Matches($Text, "(?m)^\s*measure\s+(?:'((?:''|[^'])*)'|([^\r\n=]+?))(?:\s*=|\s*$)")
    $blocks = @()

    for ($i = 0; $i -lt $matches.Count; $i++) {
        $match = $matches[$i]
        $name = if ($match.Groups[1].Success) {
            $match.Groups[1].Value.Replace("''", "'")
        } else {
            $match.Groups[2].Value.Trim()
        }

        $start = $match.Index
        $end = if ($i -lt $matches.Count - 1) { $matches[$i + 1].Index } else { $Text.Length }
        $line = ($Text.Substring(0, $start) -split "`r?`n").Count
        $body = $Text.Substring($start, $end - $start)

        $blocks += [PSCustomObject]@{
            Name = $name
            File = $FileName
            Line = $line
            Body = $body
            Start = $start
            End = $end
        }
    }

    return $blocks
}

function Get-ParentReportDirectories {
    $reportDirs = Get-ChildItem -Path $Root -Recurse -Directory -Filter "*.Report"

    return @($reportDirs | Where-Object {
        $pbir = Join-Path $_.FullName "definition.pbir"
        if (-not (Test-Path -LiteralPath $pbir)) {
            return $false
        }

        $content = Read-Utf8 $pbir
        return ($content -match [regex]::Escape($ParentSemanticModelId)) -or
            ($content -match '"path"\s*:\s*"\.\./Pilotage Mensuelv3\.SemanticModel"')
    })
}

function Get-AllReportDirectories {
    return @(Get-ChildItem -Path $Root -Recurse -Directory -Filter "*.Report")
}

function Get-CandidateMeasures {
    param([object[]]$Blocks, [System.Collections.Generic.HashSet[string]]$MeasureNames)

    $reportUsage = @{}
    foreach ($dir in Get-AllReportDirectories) {
        $projectName = Split-Path (Split-Path $dir.FullName -Parent) -Leaf
        $used = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
        $definition = Join-Path $dir.FullName "definition"

        if (Test-Path -LiteralPath $definition) {
            $files = Get-ChildItem -LiteralPath $definition -Recurse -File -Include "*.json" -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                $text = Read-Utf8 $file.FullName

                foreach ($match in [regex]::Matches($text, '(?s)"Measure"\s*:\s*\{.*?"Property"\s*:\s*"((?:\\"|[^"])*)"')) {
                    $measure = [regex]::Unescape($match.Groups[1].Value)
                    if ($MeasureNames.Contains($measure)) {
                        [void]$used.Add($measure)
                    }
                }

                foreach ($match in [regex]::Matches($text, '"queryRef"\s*:\s*"Mesure\.((?:\\"|[^"])*)"')) {
                    $measure = [regex]::Unescape($match.Groups[1].Value)
                    if ($MeasureNames.Contains($measure)) {
                        [void]$used.Add($measure)
                    }
                }
            }
        }

        $reportUsage[$projectName] = $used
    }

    $dependencies = @{}
    foreach ($block in $Blocks) {
        $set = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
        foreach ($match in [regex]::Matches($block.Body, "(?<![A-Za-z0-9_'\]])\[([^\]]+)\]")) {
            $ref = $match.Groups[1].Value
            if ($MeasureNames.Contains($ref) -and $ref -ine $block.Name) {
                [void]$set.Add($ref)
            }
        }
        $dependencies[$block.Name] = $set
    }

    $directUsed = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $reportUsage.GetEnumerator()) {
        foreach ($name in $entry.Value) {
            [void]$directUsed.Add($name)
        }
    }

    $required = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
    $queue = New-Object System.Collections.Queue
    foreach ($name in $directUsed) {
        [void]$required.Add($name)
        $queue.Enqueue($name)
    }

    while ($queue.Count -gt 0) {
        $current = [string]$queue.Dequeue()
        if ($dependencies.ContainsKey($current)) {
            foreach ($dependency in $dependencies[$current]) {
                if (-not $required.Contains($dependency)) {
                    [void]$required.Add($dependency)
                    $queue.Enqueue($dependency)
                }
            }
        }
    }

    $candidates = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
    foreach ($block in $Blocks) {
        if (-not $required.Contains($block.Name)) {
            [void]$candidates.Add($block.Name)
        }
    }

    return $candidates
}

function Get-Folder {
    param([string]$Name, [string]$Body, [bool]$Candidate)

    if ($Candidate) {
        return "À vérifier"
    }

    $haystack = ($Name + " " + $Body).ToLowerInvariant()

    if ($haystack -match "html|narratif|soustitre|titre gestion|couleur") {
        return "Restitution"
    }
    if ($haystack -match "objectif|obj_|intéressement|interessement|plafond") {
        return "Objectifs"
    }
    if ($haystack -match "assur") {
        return "Assurances"
    }
    if ($haystack -match "vacance|vac |txvac|totalvacance|mel|strat|tech") {
        if ($haystack -match "financi|loyer|quitt") {
            return "Vacance\Financière"
        }
        return "Vacance\Physique"
    }
    if ($haystack -match "encaisse|recouv|règlement|reglement|paiement|quittancement|quitm|alloc") {
        return "Encaissement et quittancement"
    }
    if ($haystack -match "dette|impay|soldem|passage.en.perte|pp ytd|croissance.*solde") {
        return "Dette et impayés"
    }
    if ($haystack -match "entrée|entree|sortie|mobilité|mobilite|mutation|peuplement|salari") {
        return "Occupation et mobilité"
    }
    if ($haystack -match "patrimoine|logement|commerce|bâtiment|batiment|ug|livraison|vente|acquisition|réhab|rehab|parcelle|densité|densite|pauvreté|pauvrete") {
        return "Patrimoine"
    }
    if ($haystack -match "réclamation|reclamation|satisfaction|affaire") {
        return "Activité et qualité de service"
    }
    if ($haystack -match "etp|cdi|absence|absent|salaire|insertion") {
        return "RH et insertion"
    }
    if ($haystack -match "date|mois|année|annee|ytd|m-1|n-1|last|previous|sameperiodlastyear|dateadd") {
        return "Temps"
    }

    return "Indicateurs généraux"
}

function Get-Description {
    param([string]$OldName, [string]$NewName, [string]$Folder, [string]$Body, [bool]$Candidate)

    $haystack = ($OldName + " " + $NewName + " " + $Body).ToLowerInvariant()
    if ($Candidate) {
        return "À vérifier avant usage. Cette mesure n'a pas été retrouvée dans les rapports analysés et doit être confirmée avec le métier. Elle est conservée temporairement pour éviter de supprimer un calcul potentiellement utile."
    }
    $prefix = ""

    $timeSuffix = ""
    if ($haystack -match "m-1|mois précédent|mois precedent|dateadd\(.*-1,\s*month") {
        $timeSuffix = " La comparaison se fait avec le mois précédent."
    } elseif ($haystack -match "sameperiodlastyear|n-1|ly|année précédente|annee precedente") {
        $timeSuffix = " La comparaison se fait avec la même période de l'année précédente."
    } elseif ($haystack -match "ytd|totalytd|cumul annuel") {
        $timeSuffix = " Le résultat est cumulé depuis le début de l'année."
    }

    $base = if ($Folder -eq "À vérifier") {
        "Elle est conservée temporairement pour éviter de supprimer un calcul potentiellement utile."
    } elseif ($Folder -like "Vacance*") {
        if ($haystack -match "taux|%|divide|/") {
            "Indique la part de vacance par rapport au volume de référence, pour suivre le niveau de vacance."
        } elseif ($haystack -match "nombre|#|distinctcount|countrows") {
            "Compte les logements, commerces ou unités concernés par une situation de vacance."
        } else {
            "Mesure le montant ou le volume lié à la vacance."
        }
    } elseif ($Folder -eq "Encaissement et quittancement") {
        if ($haystack -match "taux|recouv|encaisse") {
            "Suit la part des sommes encaissées par rapport aux sommes attendues."
        } else {
            "Additionne les montants facturés, encaissés ou liés aux allocations."
        }
    } elseif ($Folder -eq "Dette et impayés") {
        if ($haystack -match "taux|%|ratio") {
            "Indique une proportion liée aux impayés ou à l'évolution de la dette."
        } else {
            "Suit les montants restant dus, les impayés ou leur évolution."
        }
    } elseif ($Folder -eq "Occupation et mobilité") {
        if ($haystack -match "taux|%|mobil") {
            "Mesure la part ou le rythme des mouvements d'occupation."
        } else {
            "Compte les entrées, sorties ou mouvements des locataires."
        }
    } elseif ($Folder -eq "Patrimoine") {
        if ($haystack -match "nombre|#|distinctcount|countrows") {
            "Compte des éléments du patrimoine comme les logements, commerces, bâtiments ou unités de gestion."
        } else {
            "Suit un indicateur descriptif du patrimoine."
        }
    } elseif ($Folder -eq "Objectifs") {
        "Sert à comparer un résultat à un objectif de pilotage."
    } elseif ($Folder -eq "Assurances") {
        "Suit la couverture assurantielle des locataires ou des logements."
    } elseif ($Folder -eq "Restitution") {
        "Sert à afficher un texte, une couleur ou un contenu de restitution dans le rapport."
    } elseif ($Folder -eq "RH et insertion") {
        "Suit un indicateur lié aux effectifs, à l'emploi ou à l'insertion."
    } elseif ($Folder -eq "Activité et qualité de service") {
        "Suit un volume d'activité ou un indicateur de qualité de service."
    } elseif ($Folder -eq "Temps") {
        "Sert à comparer ou cumuler un indicateur dans le temps."
    } else {
        if ($haystack -match "taux|%|divide|/") {
            "Indique une proportion simple à interpréter."
        } elseif ($haystack -match "distinctcount|countrows|nombre|#") {
            "Compte un nombre d'éléments distincts."
        } elseif ($haystack -match "sum|€|montant") {
            "Additionne des montants ou des valeurs."
        } else {
            "Indicateur métier utilisé pour le pilotage."
        }
    }

    return Normalize-Spaces ($prefix + $base + $timeSuffix)
}

function Convert-MeasureName {
    param([string]$OldName, [bool]$Candidate)

    if ($Candidate) {
        return $OldName
    }

    $manual = @{
        "# UG" = "Nombre d'UG"
        "# Livraisons mensuelles" = "Nombre de livraisons mensuelles"
        "# Logements Vacants" = "Nombre de logements vacants"
        "variation dette" = "Variation mensuelle de la dette"
        "Tx_recouvrement_impayé" = "Taux de recouvrement des impayés"
        "Soldem1_ca_operation_+" = "Dette positive du mois précédent"
        "Soldem_ca_operation_+ hpp" = "Dette positive hors passages en perte"
        "% croissance_soldem_ca_operation_+" = "Taux de variation de la dette positive"
        "CumulPassagesEnPerteAnnuel" = "Passages en perte cumulés annuels historique"
        "PPM1" = "Passages en perte du mois précédent"
        "€ Croissance soldem_ca_operation" = "Variation mensuelle de la dette historique"
        "€ Quitm_ca_operation" = "Quittancement mensuel"
        "Tx Encaissement hpp soldes_ca_operation" = "Taux d'encaissement hors passages en perte"
        "CroissanceSoldem_CA_Operation_YTD" = "Variation de dette cumulée annuelle"
        "CumulQuitm_CA_Operation_YTD" = "Quittancement cumulé annuel"
        "tx encaissement YTD" = "Taux d'encaissement cumulé annuel"
        "Objectif Plafond Annuel Dette Loc" = "Objectif annuel de dette locataires"
        "Soldem_ca_operation_+_LOC" = "Dette positive des locataires"
        "Entrées YTD" = "Entrées cumulées annuelles"
        "Sorties_YTD" = "Sorties cumulées annuelles"
        "Sorties_12M" = "Sorties sur douze mois"
        "Taux_Mobilité_YoY_YTD_Dyn" = "Taux de mobilité cumulé comparé à l'année précédente"
        "NbCA_AL" = "Nombre de contrats avec allocation logement"
        "Encaissement + alloc" = "Encaissement avec allocations"
        "Nb ménage en impayé" = "Nombre de ménages en impayé"
        "NombreCodeCADistinctsAvec3*Dette" = "Nombre de contrats avec dette élevée"
        "MontantTotal3*Dette_SUMX" = "Montant total des dettes élevées"
        "Vacance commerciale" = "Nombre de logements en vacance commerciale"
        "Vacance globale" = "Nombre de logements vacants"
        "Entrées salariés YTD" = "Entrées de salariés cumulées annuelles"
        "Entrées salariés" = "Entrées de salariés"
        "obj_2024_dette" = "Objectif 2024 de dette"
        "obj_2024-vacancefi" = "Objectif 2024 de vacance financière"
        "Objectif_Total_Dette" = "Objectif total de dette"
        "Objectif_Total_Vacance" = "Objectif total de vacance"
        "Obj_entrees_salaries" = "Objectif d'entrées de salariés"
        "Dep_object_salaries" = "Taux d'atteinte de l'objectif d'entrées de salariés"
        "Variation de Ratio intéressement vac fi com par xAgence" = "Variation du ratio d'intéressement vacance financière par agence"
        "Soldem_ca_operation_+ yc PP" = "Dette positive avec passages en perte"
        "Entrées YTD LOC" = "Entrées locataires cumulées annuelles"
        "vacance fi YTD recalcul" = "Taux de vacance financière recalculé cumulé annuel"
        "tx encaissement ytd recalcul" = "Taux d'encaissement recalculé cumulé annuel"
        "€ Dette" = "Dette"
        "€ Dette HPP" = "Dette hors passages en perte"
        "€ Quittancement" = "Quittancement"
        "€ Quittancement YTD" = "Quittancement cumulé annuel"
        "€ Croissance annuelle Dette" = "Variation annuelle de la dette"
        "Taux Encaissement YTD" = "Taux d'encaissement cumulé annuel"
        "% Taux Encaissement Mensuel" = "Taux d'encaissement mensuel"
        "Impayé des présents" = "Dette des locataires présents"
        "Impayé des Partis" = "Dette des locataires partis"
        "Mobilité N-1" = "Mobilité année précédente"
        "Mobilité 1a" = "Mobilité sur douze mois"
        "Mobilité YTD new" = "Mobilité cumulée annuelle"
        "# Mutations YTD" = "Mutations cumulées annuelles"
        "# Entrées YTD" = "Entrées cumulées annuelles"
        "# Entrées LOC YTD" = "Entrées locataires cumulées annuelles"
        "# Entrées Salariés YTD" = "Entrées de salariés cumulées annuelles"
        "Vacance Financière Logements M" = "Vacance financière logements mensuelle"
        "Vacance Financière Logements YTD" = "Vacance financière logements cumulée annuelle"
        "Vacance Financière Logements YTD LY" = "Vacance financière logements cumulée annuelle précédente"
        "€ Quittancement YTD Logement" = "Quittancement logements cumulé annuel"
        "% Vacance Financière Logements YTD" = "Taux de vacance financière logements cumulé annuel"
        "Quittancement Logements M" = "Quittancement logements mensuel"
        "% Vacance Financière Logements M" = "Taux de vacance financière logements mensuel"
        "Quittancement Commerces" = "Quittancement commerces mensuel"
        "Quittancement Commerces YTD" = "Quittancement commerces cumulé annuel"
        "# Bâtiments" = "Nombre de bâtiments"
        "Dette HPP M-1" = "Dette hors passages en perte du mois précédent"
        "Quittancement m1" = "Quittancement du mois précédent"
        "Vacance financière MEL LGT" = "Vacance financière logements en mise en location"
        "Vacance financière MEL LGT YTD" = "Vacance financière logements en mise en location cumulée annuelle"
        "Indice de densité urbaine" = "Indice de densité urbaine"
        "Tx d'assurés n-1" = "Taux d'assurés année précédente"
        "# Individuels" = "Nombre de logements individuels"
        "# Collectifs" = "Nombre de logements collectifs"
        "Tx dématérialisation" = "Taux de dématérialisation"
        "Entrées en 2025" = "Entrées en 2025"
        "% Taux Encaissement YTD M-1" = "Taux d'encaissement cumulé annuel du mois précédent"
        "% Vacance Financière Logements YTD M-1" = "Taux de vacance financière logements cumulé annuel du mois précédent"
        "% Vacance Financière Logements M-1" = "Taux de vacance financière logements du mois précédent"
        "Mobilité 1a N-1" = "Mobilité sur douze mois année précédente"
        "Mobilité m-1" = "Mobilité du mois précédent"
        "Couleur salariés" = "Couleur des entrées de salariés"
        "Couleur vacance" = "Couleur de la vacance"
        "Couleur dette" = "Couleur de la dette"
        "Narratif HTML" = "Narratif HTML"
        "Titre Gestion Locative HTML" = "Titre HTML gestion locative"
        "SousTitre HTML Patrimoine" = "Sous-titre HTML patrimoine"
        "SousTitre HTML Détail vacance" = "Sous-titre HTML détail vacance"
        "SousTitre HTML Détail impayé" = "Sous-titre HTML détail impayé"
        "SousTitre HTML Flux d'occupation" = "Sous-titre HTML flux d'occupation"
        "SousTitre HTML Quittancement et impayé" = "Sous-titre HTML quittancement et impayé"
        "SousTitre HTML Vacance financière logements" = "Sous-titre HTML vacance financière logements"
        "SousTitre HTML Vacance physique logements" = "Sous-titre HTML vacance physique logements"
    }

    $manual["# Affaires"] = "Nombre d'affaires"
    $manual["#AffairesTerminéesDansLesTemps"] = "Affaires terminées dans les temps"
    $manual["#AffairesTerminéesEnRetard"] = "Affaires terminées en retard"
    $manual["# AffairesTraitées"] = "Nombre d'affaires traitées"
    $manual["%AffairesTerminéesDansLesTemps"] = "Taux d'affaires terminées dans les temps"
    $manual["Dette Partis M-1"] = "Dette des locataires partis du mois précédent"
    $manual["Dette Présents M-1"] = "Dette des locataires présents du mois précédent"
    $manual["Soldem_ca_operation_+_Partis"] = "Dette positive des locataires partis"
    $manual["Soldem_ca_operation_+_Present"] = "Dette positive des locataires présents"
    $manual["MoisDecembrePrecedent"] = "Mois de décembre précédent"
    $manual["€ Croissance Dette"] = "Variation mensuelle de la dette"
    $manual["% Croissance annuelle"] = "Taux de croissance annuel"
    $manual["% Croissance annuelle Dette"] = "Taux de croissance annuelle de la dette"
    $manual["% Croissance dette M"] = "Taux de croissance mensuelle de la dette"
    $manual["% croissance_soldem_ca_operation_+_uniquement positif"] = "Taux de croissance de la dette positive"
    $manual["€ PP"] = "Passages en perte"
    $manual["€ PP YTD"] = "Passages en perte cumulés annuels"
    $manual["Encaissement + AL"] = "Encaissement avec allocations logement"
    $manual["Encaissements + AL cumulés"] = "Encaissements avec allocations logement cumulés"
    $manual["€ Quittancement logements et commerces M"] = "Quittancement logements et commerces mensuel"
    $manual["€ Quittancement logements et commerces YTD"] = "Quittancement logements et commerces cumulé annuel"
    $manual["€ Quittancement YTD"] = "Quittancement cumulé annuel"
    $manual["CumulQuitm_CA_Operation_YTD"] = "Quittancement cumulé annuel historique"
    $manual["Règlements HPP M-12"] = "Règlements hors passages en perte douze mois avant"
    $manual["Tx Croissance M-1 (%)"] = "Taux de croissance du mois précédent"
    $manual["Tx Croissance M-12 (%)"] = "Taux de croissance douze mois avant"
    $manual["Taux Encaissement YTD"] = "Taux d'encaissement cumulé annuel"
    $manual["tx encaissement YTD"] = "Taux d'encaissement cumulé annuel historique"
    $manual["% Taux Encaissement Mensuel LY"] = "Taux d'encaissement mensuel année précédente"
    $manual["% Taux Encaissement YTD LY"] = "Taux d'encaissement cumulé annuel année précédente"
    $manual["Taux Règlements HPP CB M"] = "Taux de règlements CB mensuel hors passages en perte"
    $manual["Taux Règlements HPP Chèque M"] = "Taux de règlements par chèque mensuel hors passages en perte"
    $manual["Taux Règlements HPP Espèces M"] = "Taux de règlements en espèces mensuel hors passages en perte"
    $manual["Taux Règlements HPP IBAN M"] = "Taux de règlements IBAN mensuel hors passages en perte"
    $manual["Taux Règlements HPP Prélèvements M"] = "Taux de règlements par prélèvement mensuel hors passages en perte"
    $manual["Taux Règlements HPP Virements M"] = "Taux de règlements par virement mensuel hors passages en perte"
    $manual["% Dép objectif dette loc YTD"] = "Taux d'atteinte de l'objectif dette locataires cumulé annuel"
    $manual["% Dép obj vacance logement"] = "Taux d'atteinte de l'objectif vacance logements"
    $manual["Entrées YTD"] = "Entrées cumulées annuelles historiques"
    $manual["# Entrées YTD"] = "Nombre d'entrées cumulées annuelles"
    $manual["# Entrées Salariés YTD"] = "Nombre d'entrées de salariés cumulées annuelles"
    $manual["Mobilité 1a"] = "Mobilité sur un an"
    $manual["Mobilité 12m"] = "Mobilité sur douze mois"
    $manual["# Entrées"] = "Nombre d'entrées"
    $manual["# Sorties"] = "Nombre de sorties"
    $manual["# Commerces"] = "Nombre de commerces"
    $manual["# Commerces 2024"] = "Nombre de commerces en 2024"
    $manual["# Commerces m-1"] = "Nombre de commerces du mois précédent"
    $manual["# Commerces vacants"] = "Nombre de commerces vacants"
    $manual["Nb d'étages"] = "Nombre d'étages"
    $manual["# Livraisons M"] = "Nombre de livraisons mensuelles"
    $manual["# Livraisons M"] = "Nombre de livraisons logements mensuelles"
    $manual["# Logements"] = "Nombre de logements"
    $manual["# Logements et commerces contractés"] = "Nombre de logements et commerces contractés"
    $manual["# Logements m-1"] = "Nombre de logements du mois précédent"
    $manual["# Loges"] = "Nombre de loges"
    $manual["Nb T5+"] = "Nombre de T5 et plus"
    $manual["# UG Vacants VVO"] = "Nombre d'UG vacantes volontaires"
    $manual["# UG Vacance Ordinaire"] = "Nombre d'UG en vacance ordinaire"
    $manual["# UG Vacants Technique"] = "Nombre d'UG en vacance technique"
    $manual["Nb UG Vac Plus 3 Mois"] = "Nombre d'UG vacantes depuis plus de trois mois"
    $manual["# Logements Vacants Commercial"] = "Nombre de logements vacants en commercial"
    $manual["# Logements Vacants Stratégique"] = "Nombre de logements en vacance stratégique"
    $manual["Vacance globale"] = "Nombre total de logements vacants"
    $manual["% Vac com commerces"] = "Taux de vacance commerciale des commerces"
    $manual["MontantTotal3*vacance_SUMX"] = "Montant total des vacances élevées"
    $manual["% Tx Vac Comm YTD"] = "Taux de vacance commerciale cumulé annuel"
    $manual["% Tx Vac Strat Fi YTD"] = "Taux de vacance financière stratégique cumulé annuel"
    $manual["% Tx Vac Tech Fi YTD"] = "Taux de vacance financière technique cumulé annuel"
    $manual["% Tx Vac Fi YTD"] = "Taux de vacance financière cumulé annuel"
    $manual["% Tx Vac Fi mensuelle"] = "Taux de vacance financière mensuel"
    $manual["Vacance Financière Commerce et Logement TCC M"] = "Vacance financière commerces et logements mensuelle"
    $manual["Vacance Financière Commerce et Logement TCC YTD"] = "Vacance financière commerces et logements cumulée annuelle"
    $manual["Vacance Financière Commerces M"] = "Vacance financière commerces mensuelle"
    $manual["VacanceFinanciereYTDRecalcule"] = "Vacance financière recalculée cumulée annuelle"
    $manual["VacanceFinanciereYTDRecalculeHC"] = "Vacance financière hors charges recalculée cumulée annuelle"
    $manual["TotalVacanceComm_ug"] = "Vacance commerciale totale par UG"
    $manual["TotalVacanceDemol_ug"] = "Vacance liée aux démolitions par UG"
    $manual["TotalVacanceStrat_ug"] = "Vacance stratégique totale par UG"
    $manual["TotalVacanceTech_ug"] = "Vacance technique totale par UG"
    $manual["TotalVacanceVendu_ug"] = "Vacance liée aux ventes par UG"

    if ($manual.ContainsKey($OldName)) {
        return $manual[$OldName]
    }

    $name = $OldName
    $name = $name -replace "_", " "
    $name = $name -replace "&", " et "
    $name = $name -creplace "([a-zà-ÿ])([A-Z])", '$1 $2'
    $name = $name -replace "^#\s*", "Nombre de "
    $name = $name -replace "^€\s*", "Montant "
    $name = $name -replace "^%\s*", "Taux "
    $name = $name -replace "\bTx\b", "Taux"
    $name = $name -replace "\btx\b", "Taux"
    $name = $name -replace "txrecouv", "Taux recouvrement"
    $name = $name -replace "tximpaye", "Taux impayé"
    $name = $name -replace "YTD", "cumul annuel"
    $name = $name -replace "\bLY\b", "année précédente"
    $name = $name -replace "N-1", "année précédente"
    $name = $name -replace "M-12", "douze mois avant"
    $name = $name -replace "M-1", "mois précédent"
    $name = $name -replace "\bM1\b", "mois précédent"
    $name = $name -replace "\b12m\b", "sur douze mois"
    $name = $name -replace "\b12M\b", "sur douze mois"
    $name = $name -replace "\bHpp\b", "hors passages en perte"
    $name = $name -replace "\bHPP\b", "hors passages en perte"
    $name = $name -replace "hpp", "hors passages en perte"
    $name = $name -replace "soldem ca operation \+", "dette positive"
    $name = $name -replace "soldem ca operation", "dette"
    $name = $name -replace "Soldem ca operation \+", "Dette positive"
    $name = $name -replace "Soldem ca operation", "Dette"
    $name = $name -replace "Croissance Soldem CA Operation", "Variation de dette"
    $name = $name -replace "Quitm ca operation", "Quittancement"
    $name = $name -replace "quitm ca operation", "quittancement"
    $name = $name -replace "\bVac fi\b", "vacance financière"
    $name = $name -replace "VacanceFinanciere", "Vacance financière"
    $name = $name -replace "VacanceFinancière", "Vacance financière"
    $name = $name -replace "\bFim\b", "financière mensuelle"
    $name = $name -replace "\bFi\b", "financière"
    $name = $name -replace "\bLGT\b", "logements"
    $name = $name -replace "\bLOC\b", "locataires"
    $name = $name -replace "\bCOM\b", "commerces"
    $name = $name -replace "\bComm\b", "commerciale"
    $name = $name -replace "\bMEL\b", "mise en location"
    $name = $name -replace "\bStrat\b", "stratégique"
    $name = $name -replace "\bTech\b", "technique"
    $name = $name -replace "\bNb\b", "Nombre de"
    $name = $name -replace "\bobj\b", "Objectif"
    $name = $name -replace "\bDep object\b", "Taux d'atteinte de l'objectif"
    $name = $name -replace " 2024", " 2024"
    $name = $name -replace "\s+:", ""
    $name = $name -replace "\+", "avec"
    $name = $name -replace "\*", "fois"
    $name = $name -replace "\bca\b", "contrats"
    $name = $name -replace "\bCA\b", "contrats"
    $name = $name -replace "\bM\b", "mensuel"
    $name = $name -replace "Taux Taux", "Taux"
    $name = $name -replace "Nombre de de ", "Nombre de "
    $name = Normalize-Spaces $name

    if ($name.Length -gt 0) {
        $name = $name.Substring(0, 1).ToUpperInvariant() + $name.Substring(1)
    }

    return $name
}

function Rename-MeasureDeclarations {
    param([string]$Text, [hashtable]$RenameMap)

    $pattern = "(?m)^(\s*)measure\s+(?:'((?:''|[^'])*)'|([^\r\n=]+?))(?<tail>\s*=.*|\s*)$"
    return [regex]::Replace($Text, $pattern, {
        param($match)
        $oldName = if ($match.Groups[2].Success) {
            $match.Groups[2].Value.Replace("''", "'")
        } else {
            $match.Groups[3].Value.Trim()
        }

        if (-not $RenameMap.ContainsKey($oldName)) {
            return $match.Value
        }

        $newName = $RenameMap[$oldName]
        if ($newName -eq $oldName) {
            return $match.Value
        }

        return $match.Groups[1].Value + "measure '" + (Escape-TmdlName $newName) + "'" + $match.Groups["tail"].Value
    })
}

function Update-MeasureMetadata {
    param([string]$Text, [hashtable]$RowsByNewName)

    $blocks = Get-MeasureBlocks -Text $Text
    $builder = New-Object System.Text.StringBuilder
    $position = 0

    foreach ($block in $blocks) {
        [void]$builder.Append($Text.Substring($position, $block.Start - $position))

        $measureBlock = $Text.Substring($block.Start, $block.End - $block.Start)
        if ($RowsByNewName.ContainsKey($block.Name)) {
            $row = $RowsByNewName[$block.Name]
            $measureBlock = [regex]::Replace($measureBlock, "(?m)^\s*description:\s*.*\r?\n", "")
            $measureBlock = [regex]::Replace($measureBlock, "(?m)^\s*displayFolder:\s*.*\r?\n", "")

            $description = ($row.Description -replace "[\r\n]+", " ")
            $description = Normalize-Spaces $description
            $folder = Normalize-Spaces $row.Folder
            $metadata = "`t`tdescription: $description`r`n`t`tdisplayFolder: $folder`r`n"

            $propertyMatch = [regex]::Match($measureBlock, "(?m)^\s*(formatString|lineageTag|annotation|isHidden|summarizeBy):")
            if ($propertyMatch.Success) {
                $measureBlock = $measureBlock.Insert($propertyMatch.Index, $metadata)
            } else {
                $trimmed = $measureBlock.TrimEnd()
                $trailing = $measureBlock.Substring($trimmed.Length)
                $measureBlock = $trimmed + "`r`n" + $metadata + $trailing
            }
        }

        [void]$builder.Append($measureBlock)
        $position = $block.End
    }

    [void]$builder.Append($Text.Substring($position))
    return $builder.ToString()
}

function Replace-MeasureReferencesInText {
    param([string]$Text, [object[]]$Rows)

    $updated = $Text
    foreach ($row in ($Rows | Where-Object { $_.OldName -ne $_.NewName } | Sort-Object { $_.OldName.Length } -Descending)) {
        $updated = $updated.Replace("[" + $row.OldName + "]", "[" + $row.NewName + "]")
    }
    return $updated
}

function Replace-MeasureReferencesInReportJson {
    param([string]$Text, [object[]]$Rows)

    $updated = $Text
    foreach ($row in ($Rows | Where-Object { $_.OldName -ne $_.NewName } | Sort-Object { $_.OldName.Length } -Descending)) {
        $old = Escape-JsonString $row.OldName
        $new = Escape-JsonString $row.NewName

        $updated = $updated.Replace('"Property": "' + $old + '"', '"Property": "' + $new + '"')
        $updated = $updated.Replace('"nativeQueryRef": "' + $old + '"', '"nativeQueryRef": "' + $new + '"')
        $updated = $updated.Replace('"queryRef": "Mesure.' + $old + '"', '"queryRef": "Mesure.' + $new + '"')
        $updated = $updated.Replace("[" + $row.OldName + "]", "[" + $row.NewName + "]")
    }
    return $updated
}

$measureText = Read-Utf8 $MeasurePath
$blocks = @(Get-MeasureBlocks -Text $measureText)
$measureNames = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
foreach ($block in $blocks) {
    [void]$measureNames.Add($block.Name)
}

$candidateMeasures = Get-CandidateMeasures -Blocks $blocks -MeasureNames $measureNames
$rows = @()
$usedNewNames = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)

foreach ($block in $blocks) {
    $isCandidate = $candidateMeasures.Contains($block.Name)
    $folder = Get-Folder -Name $block.Name -Body $block.Body -Candidate $isCandidate
    $newName = Convert-MeasureName -OldName $block.Name -Candidate $isCandidate

    if (-not $isCandidate) {
        $baseName = $newName
        $counter = 2
        while ($usedNewNames.Contains($newName)) {
            $newName = "$baseName ($counter)"
            $counter++
        }
    }

    [void]$usedNewNames.Add($newName)
    $description = Get-Description -OldName $block.Name -NewName $newName -Folder $folder -Body $block.Body -Candidate $isCandidate

    $rows += [PSCustomObject]@{
        OldName = $block.Name
        NewName = $newName
        Folder = $folder
        Description = $description
        Candidate = $isCandidate
        Line = $block.Line
    }
}

$rows |
    Sort-Object Candidate, Folder, NewName |
    Export-Csv -LiteralPath $MappingPath -NoTypeInformation -Encoding UTF8

if (-not $Apply) {
    Write-Host "Plan genere : $MappingPath"
    Write-Host "Mesures analysees : $($rows.Count)"
    Write-Host "Mesures renommees : $(($rows | Where-Object { $_.OldName -ne $_.NewName }).Count)"
    Write-Host "Mesures conservees dans A verifier : $(($rows | Where-Object { $_.Candidate }).Count)"
    exit 0
}

$renameMap = @{}
foreach ($row in $rows) {
    $renameMap[$row.OldName] = $row.NewName
}

$rowsByNewName = @{}
foreach ($row in $rows) {
    $rowsByNewName[$row.NewName] = $row
}

$measureText = Rename-MeasureDeclarations -Text $measureText -RenameMap $renameMap
$measureText = Replace-MeasureReferencesInText -Text $measureText -Rows $rows
$measureText = Update-MeasureMetadata -Text $measureText -RowsByNewName $rowsByNewName
Write-Utf8NoBom -Path $MeasurePath -Text $measureText

$tmdlFiles = Get-ChildItem -LiteralPath $SemanticModelRoot -Recurse -File -Filter "*.tmdl" |
    Where-Object { $_.FullName -ne $MeasurePath }

foreach ($file in $tmdlFiles) {
    $text = Read-Utf8 $file.FullName
    $updated = Replace-MeasureReferencesInText -Text $text -Rows $rows
    if ($updated -ne $text) {
        Write-Utf8NoBom -Path $file.FullName -Text $updated
    }
}

$parentReports = Get-ParentReportDirectories
foreach ($dir in $parentReports) {
    $definition = Join-Path $dir.FullName "definition"
    if (-not (Test-Path -LiteralPath $definition)) {
        continue
    }

    $files = Get-ChildItem -LiteralPath $definition -Recurse -File -Include "*.json" -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $text = Read-Utf8 $file.FullName
        $updated = Replace-MeasureReferencesInReportJson -Text $text -Rows $rows
        if ($updated -ne $text) {
            Write-Utf8NoBom -Path $file.FullName -Text $updated
        }
    }
}

Write-Host "Harmonisation appliquee."
Write-Host "Mesures analysees : $($rows.Count)"
Write-Host "Mesures renommees : $(($rows | Where-Object { $_.OldName -ne $_.NewName }).Count)"
Write-Host "Mesures conservees dans A verifier : $(($rows | Where-Object { $_.Candidate }).Count)"
Write-Host "Rapports parent mis a jour : $($parentReports.Count)"
