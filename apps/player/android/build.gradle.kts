import java.security.MessageDigest

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

val mediaKitAndroidAudioCacheDir =
    providers.gradleProperty("mediaKitAndroidAudioCacheDir").orNull
        ?: providers.environmentVariable("MEDIA_KIT_ANDROID_AUDIO_CACHE_DIR").orNull
        ?: "../../../dist/build-cache/media-kit/android-audio"
val mediaKitAndroidAudioCacheDirectory = rootProject.file(mediaKitAndroidAudioCacheDir)
val mediaKitAndroidAudioArtifacts =
    mapOf(
        "default-arm64-v8a.jar" to "0481a64b5e246774da22573d7a4e67f9fb3d89a68630864d8819d3ff3a08bb09",
        "default-armeabi-v7a.jar" to "1bba852f5b7f0098c54ab8c3a945866d2b730b9e146b472a6ffaa80fc0dceae9",
        "default-x86_64.jar" to "ddffa0465e2dbb42d52937dae08516dbe07c534d489e9ea995f36a02d31a7106",
        "default-x86.jar" to "824deeee316dfa3085832c6308e2953425bd428ba7eeeefd59bb51101b7ce8b7",
    )

fun sha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().buffered().use { input ->
        val buffer = ByteArray(8192)
        while (true) {
            val bytesRead = input.read(buffer)
            if (bytesRead < 0) {
                break
            }
            digest.update(buffer, 0, bytesRead)
        }
    }
    return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
}

subprojects {
    if (project.name == "media_kit_libs_android_audio") {
        val versionDirectory = mediaKitAndroidAudioCacheDirectory.resolve("v1.1.8")
        mediaKitAndroidAudioArtifacts.forEach { (name, expectedSha256) ->
            val artifact = versionDirectory.resolve(name)
            require(artifact.isFile && sha256(artifact) == expectedSha256) {
                "Missing or invalid media_kit Android artifact: $artifact. " +
                    "Run scripts/cache-media-kit.ps1 before the Android release build."
            }
        }

        project.layout.buildDirectory.fileValue(mediaKitAndroidAudioCacheDirectory)
        project.tasks.matching { it.name == "downloadDependencies" }.configureEach {
            enabled = false
        }
    } else {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
