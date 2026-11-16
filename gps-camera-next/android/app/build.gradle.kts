import java.util.Properties
import java.io.FileInputStream
import java.util.Base64
import java.security.KeyStore
import java.net.URI
import java.security.cert.X509Certificate
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Credentials stay local. A missing upload identity must never produce a
// debug-signed artifact labelled as a release.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val signingFields = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val hasReleaseSigning = signingFields.all {
    !keystoreProperties.getProperty(it).isNullOrBlank()
}

val validateProductionConfiguration = tasks.register("validateProductionConfiguration") {
    doLast {
        check(hasReleaseSigning) {
            "Production release blocked: provide a complete local android/key.properties and upload keystore. Debug signing is never used for release."
        }
        val store = file(keystoreProperties.getProperty("storeFile"))
        check(store.isFile) { "Production release blocked: upload keystore does not exist." }
        val keyStore = KeyStore.getInstance(store, keystoreProperties.getProperty("storePassword").toCharArray())
        val alias = keystoreProperties.getProperty("keyAlias")
        val certificate = keyStore.getCertificate(alias) as? X509Certificate
        check(certificate != null && !certificate.subjectX500Principal.name.contains("CN=Android Debug", ignoreCase = true)) {
            "Production release blocked: choose a non-debug upload signing identity."
        }
        certificate.checkValidity()
        check(keyStore.getKey(alias, keystoreProperties.getProperty("keyPassword").toCharArray()) != null) {
            "Production release blocked: upload key could not be read."
        }
        val defines = (project.findProperty("dart-defines") as? String).orEmpty()
            .split(',').filter { it.isNotBlank() }.associate {
                val value = String(Base64.getDecoder().decode(it), Charsets.UTF_8)
                value.substringBefore('=') to value.substringAfter('=', "")
            }
        val policy = runCatching { URI(defines["PRIVACY_POLICY_URL"].orEmpty()) }.getOrNull()
        fun placeholderHost(host: String): Boolean {
            val value = host.lowercase()
            return value == "localhost" || value == "127.0.0.1" || value == "[::1]" ||
                value.endsWith(".invalid") || value.endsWith(".test") ||
                listOf("example.com", "example.net", "example.org").any { value == it || value.endsWith(".$it") }
        }
        check(policy != null && policy.scheme == "https" && !policy.host.isNullOrBlank() &&
            policy.userInfo == null && !placeholderHost(policy.host)) {
            "Production release blocked: set PRIVACY_POLICY_URL to the published HTTPS privacy policy."
        }
        val contact = defines["PRIVACY_CONTACT_EMAIL"].orEmpty()
        check(contact.matches(Regex("[^\\s@]+@[^\\s@]+\\.[^\\s@]+")) && !placeholderHost(contact.substringAfter('@'))) {
            "Production release blocked: set PRIVACY_CONTACT_EMAIL to the monitored privacy contact."
        }
        check(!defines["ESRI_API_KEY"].isNullOrBlank()) {
            "Production release blocked: configure authorized ESRI_API_KEY access for the map features."
        }
        val inventoryFile = rootProject.file("../assets/legal/android-components.json")
        check(inventoryFile.isFile) { "Production release blocked: generate Android licence notices." }
        val inventory = JsonSlurper().parse(inventoryFile) as List<*>
        val documented = inventory.map { (it as Map<*, *>)["coordinate"] as String }.toSet()
        val shipped = configurations.getByName("releaseRuntimeClasspath")
            .resolvedConfiguration.resolvedArtifacts.map { it.moduleVersion.id.toString() }.toSet()
        check(documented.containsAll(shipped)) {
            "Production release blocked: Android dependency notices are stale. Run tools/generate_android_notices.py for the resolved release graph."
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(validateProductionConfiguration)
}

android {
    namespace = "com.gpscamera.gps_camera_next"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.gpscamera.gps_camera_next"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            // Installs beside the Play build, which is signed with a different key.
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                null
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    constraints {
        implementation("com.google.guava:guava:33.7.2-android") {
            because("Fix GHSA-xxph-c9ww-hj94; do not downgrade the runtime to the vulnerable CameraX transitive version.")
        }
    }
    implementation("androidx.camera:camera-camera2:1.6.0")
    implementation("androidx.media3:media3-transformer:1.9.2")
    implementation("androidx.media3:media3-effect:1.9.2")
}
