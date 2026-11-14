# Bundeslebensmittelschlüssel 4.0

The normalized seed `bls_4_0_foods.json.gz` is derived from:

> Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0 – Deutsche Nährstoffdatenbank. Karlsruhe.

- Source: https://blsdb.de/download
- DOI: https://doi.org/10.25826/Data20251217-134202-0
- License: Creative Commons Attribution 4.0 International (CC BY 4.0)
- Values: per 100 g edible portion

The seed preserves the BLS code, German and English food names, energy,
protein, fat, available carbohydrates, sugar, fibre, saturated fatty acids and
salt. BLS values marked as trace (`TR`) or below the detection/quantification
limit (`<LOD`, `<LOQ`) are normalized to `0` because PocketBase nutrient fields
are numeric.

The additional `HYSE-REF-SOLJANKA-001` record is based on the declared values
in the MHV GmbH product sheet “Original-Schulküche Schulküchen-Soljanka”. It is
kept separate from BLS, marked as a non-average reference value and documents
that homemade recipes can differ.
