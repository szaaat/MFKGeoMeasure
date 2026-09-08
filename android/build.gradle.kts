buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.7.2")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.1.10")
    }
}

import com.android.build.gradle.BaseExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
    
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions {
            freeCompilerArgs += listOf("-Xskip-metadata-version-check")
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    // 1. Force stable AndroidX versions
    configurations.all {
        resolutionStrategy {
            force("androidx.activity:activity:1.9.3")
            force("androidx.activity:activity-ktx:1.9.3")
            force("androidx.core:core:1.13.1")
            force("androidx.core:core-ktx:1.13.1")
            force("androidx.lifecycle:lifecycle-common:2.8.7")
            force("androidx.lifecycle:lifecycle-runtime:2.8.7")
            force("androidx.lifecycle:lifecycle-process:2.8.7")
        }
    }

    // 2. Early injection
    project.plugins.whenPluginAdded {
        if (this.javaClass.name.contains("com.android.build.gradle.LibraryPlugin") ||
            this.javaClass.name.contains("com.android.build.gradle.AppPlugin")) {
            
            project.extensions.configure<BaseExtension>("android") {
                compileSdkVersion(36)
                if (namespace == null) {
                    namespace = "hu.uni.miskolc.mfk_geomeasure.${project.name.replace("-", "_")}"
                }
                defaultConfig {
                    targetSdkVersion(36)
                }
            }
        }
    }

    // 3. Late Patching
    afterEvaluate {
        if (project.extensions.findByName("android") != null) {
            val android = project.extensions.getByName("android") as BaseExtension
            android.compileSdkVersion(36)
            
            // Manifest
            val manifestFile = file("src/main/AndroidManifest.xml")
            if (manifestFile.exists()) {
                try {
                    val content = manifestFile.readText()
                    if (content.contains("package=")) {
                        val regex = Regex("""package="([^"]*)"""")
                        val match = regex.find(content)
                        val originalPackage = match?.groupValues?.get(1)
                        if (originalPackage != null) {
                             android.namespace = originalPackage
                        }
                        manifestFile.writeText(content.replace(regex, ""))
                    }
                } catch (e: Exception) {}
            }

            // Patch raw_gnss
            if (project.name == "raw_gnss") {
                val pluginFile = file("src/main/java/dev/joshi/raw_gnss/RawGnssPlugin.java")
                if (pluginFile.exists()) {
                    try {
                        var content = pluginFile.readText()
                        if (content.contains("import io.flutter.plugin.common.PluginRegistry.Registrar;")) {
                            content = content.replace("import io.flutter.plugin.common.PluginRegistry.Registrar;", "//")
                            val startTag = "@RequiresApi(api = Build.VERSION_CODES.N)\n  public static void registerWith(Registrar registrar) {"
                            if (content.contains(startTag)) {
                                val startIndex = content.indexOf(startTag)
                                val endIndex = content.indexOf("}", startIndex) + 1
                                if (startIndex != -1 && endIndex > startIndex) {
                                    val block = content.substring(startIndex, endIndex)
                                    content = content.replace(block, "/* removed */")
                                }
                            }
                            pluginFile.writeText(content)
                        }
                    } catch (e: Exception) {}
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
