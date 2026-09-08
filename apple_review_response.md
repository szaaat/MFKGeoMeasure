# App Store Review Response (Resolution Center)

**Copy and paste the following text into the Resolution Center and the App Store Connect Notes field.**

---

**Subject: Response to Guideline 2.1 - Information Needed**

Dear App Review Team,

We are providing the requested information to complete the review for MFK GeoMeasure. Our app has been thoroughly tested on physical iOS devices to ensure stability and performance.

### 1. Screen Recording
We have attached a screen recording captured on a physical device running the latest iOS. 
**The recording demonstrates:**
- App launch (No login required).
- Accessing the **Map View** and obtaining a GPS fix.
- Using the **new integrated camera system** to take a field photo.
- Saving a survey point with **Dynamic Attributes** (Custom fields).
- Navigating to the **COGO Module** and performing an Inverse calculation with step-by-step derivation.
- Exporting a project to a **ZIP package** containing the data file (GeoJSON/CSV) and the specific photo for **QGIS integration**.

### 2. Purpose and Target Audience
MFK GeoMeasure is a professional tool designed for **land surveyors, GIS engineers, and university engineering students**. 
- **Problem it solves:** Real-time transformation between global WGS84 coordinates and the Hungarian National Grid (EOV), precise field data collection, and orthometric height calculation using local geoid models.
- **Value provided:** It eliminates the need for bulky equipment for preliminary field surveys and provides an interactive learning environment for geodetic students.

### 3. Setup and Access
- **Account:** The app requires **NO account registration, login, or internet connection** to access its core features.
- **Main Features:** All mapping, COGO, and measurement tools are available immediately upon launch.
- **Permissions:** The app will request Location, Camera, and Motion Sensor permissions to function, as explained in the Info.plist strings.

### 4. External Services
The app uses the following external data providers to deliver map functionality:
- **Map Tiles:** OpenStreetMap, Google Maps, and Turistautak.hu.
- These services are accessed via standard HTTPS/HTTP requests to fetch background map tiles. **No personal user data, location history, or account information is sent to these providers.**

### 5. Regional Differences
The app functions consistently across all regions globally using standard WGS84/GPS protocols. It includes **specialized optimization** (EOV Projection and EHT2014 Geoid grid) specifically for the **Hungarian region** to meet local engineering standards.

### 6. Regulated Industry / Protected Material
The app is a **mathematical and engineering calculator**. It does not operate in a highly regulated industry (like banking or healthcare). All calculations use standard, public geodetic formulas (Tienstra, Gauss, etc.).

We hope this information is sufficient to complete the review. We are committed to providing a high-quality professional tool for the surveying community.

Best regards,

**Attila Szamosi**
Developer of MFK GeoMeasure
