allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jcenter.bintray.com") }
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

    project.evaluationDependsOn(":app")

    val configureSubproject = {
        if (project.plugins.hasPlugin("com.android.library")) {
            val androidExtension = project.extensions.findByName("android") as? com.android.build.gradle.LibraryExtension
            if (androidExtension != null) {
                if (project.name.contains("flutter_bluetooth_serial")) {
                    androidExtension.namespace = "io.github.edufolly.flutterbluetoothserial"
                } else if (androidExtension.namespace == null) {
                    androidExtension.namespace = "com.plugin.${project.name.replace("-", "_")}"
                }
                androidExtension.compileSdk = 36
            }
        }
    }

    if (project.state.executed) {
        configureSubproject()
    } else {
        project.afterEvaluate { configureSubproject() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
