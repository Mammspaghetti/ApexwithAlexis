Bandeaux graphiques du gabarit ABYLSEN_AT_V11 (session 56), extraits de
docs/gabarits/SIGMA__PTF_AT_v11_FR.docx (word/media/, DPI 300).

  aby-cover-header.jpg   <- word/media/image4.jpg (2480x605) : bandeau de la page de garde
                            (dégradé vert + logo ABYLSEN "Free to explore" + filet).
                            NE CONTIENT PAS le titre "PROPOSITION TECHNIQUE ET FINANCIERE" :
                            vérifié pixel par pixel sur le PDF modèle (docs/gabarits/
                            SIGMA__PTF_AT_v11_FR1-modele-vierge.pdf, page 1) — ce titre est
                            imprimé par Word en HTML/texte à droite du filet vertical, dans
                            la zone blanche de l'image. AR_PTFTemplateAbylsen.page fait de même.

  aby-content-header.jpg <- word/media/image2.jpg (2477x399) : en-tête courant, répété sur
                            toutes les pages de contenu (cercle Abylsen + filets).
                            Le .docx source contient AUSSI image1.jpg, visuellement identique
                            (même cercle, mêmes filets) mais jamais rendu : c'est l'en-tête
                            "even page" d'une section où "pages paires/impaires différentes"
                            n'est pas activé (pas de <w:evenAndOddHeaders/> dans settings.xml).
                            Non repris ici — vérifié orphelin, cf. docs/56-socle-charte-abylsen.md §1.

  aby-cover-footer.jpg   <- word/media/image5.jpg (2479x375) : pied de la page de garde
                            uniquement (filet + bloc vert bas-droite + "www.abylsen.com").
                            Le pied courant (pages de contenu) N'EST PAS une image dans le
                            modèle Word : seul du texte centré (ABYLSEN / mention de
                            confidentialité / référence document / n° de page), sans aucun
                            graphique — vérifié sur les pages 2 à 13 du PDF modèle. Le .docx
                            source contient AUSSI image3.jpg (même bandeau + mention RCS/SIREN)
                            mais c'est le pied "even page", jamais rendu pour la même raison
                            qu'image1.jpg ci-dessus — non repris ici.

Un seul point à changer quand les fichiers officiels haute définition seront fournis par
Abylsen/le client : remplacer ces trois fichiers dans cette ressource, sans toucher aux
gabarits AR_PTFTemplateAbylsen.page / AR_PTFAvenant.page qui les référencent par nom.
