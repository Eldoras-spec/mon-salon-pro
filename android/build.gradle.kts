allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Workaround Firebase Flutter plugins (firebase_storage 13.3.0,
// firebase_app_check 0.4.3) qui ont leur `apply plugin: 'kotlin-android'`
// APRÈS leur propre `buildscript { kotlin_version = "1.8.22" }` → conflit
// avec le Kotlin 2.2.20 du projet, le Kotlin compile silencieusement
// échoue, le Java app ne trouve plus FlutterFirebaseStoragePlugin.
// On force l'application de kotlin-android dès que com.android.library
// est appliqué sur un sous-projet, AVANT que son buildscript local
// ne s'évalue.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        pluginManager.apply("org.jetbrains.kotlin.android")
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
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
