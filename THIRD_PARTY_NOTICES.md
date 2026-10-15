# Third-party geodetic data

The following offline assets are derived from datasets originating from the
Department of Geodesy and Surveying of Budapest University of Technology and
Economics, converted and distributed in the OSGeo PROJ-data `hu_bme` package:

- `assets/data/hu_bme_hd72corr.tif`
- `assets/data/hu_bme_geoid2014.tif`

The source files were verified with these SHA-256 values:

- `hu_bme_hd72corr.tif`: `7a56680fd21dd24bd869a6898b300f061b91723b21df78010f35ab1e23a77a67`
- `hu_bme_geoid2014.tif`: `0be6c660f98b5a3bf6281c44000d87e4f1d4a53a18f780931a76338c3dac1ad2`

The `.f32` assets are uncompressed Float32 caches generated from the
corresponding verified TIFFs. They contain no additional geodetic data.
Redistribution must follow the licence and attribution terms published with
the upstream BME/PROJ-data distribution. The upstream metadata specifies the
**Creative Commons Attribution 4.0 BY-SA** licence:
https://creativecommons.org/licenses/by-sa/4.0/

Source and metadata:

- BME Department of Geodesy and Surveying:
  https://geod.bme.hu/geod/onlineszolgaltatasok
- PROJ-data `hu_bme` metadata:
  https://github.com/OSGeo/PROJ-data/blob/cdab44864a36a9f3c3e90a36637c5d8a86e624c6/hu_bme/hu_bme_README.txt

The horizontal grid is documented as EPSG:4237 (HD72) to EPSG:9067
(ETRF2000), and the vertical grid as EPSG:7931 (ETRF2000) to EPSG:5787
(EOMA 1980).
