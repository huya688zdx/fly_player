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

subprojects {
    val projectRoot = project.projectDir.toPath().root?.toString()?.lowercase()
    val sharedBuildRoot = newBuildDir.asFile.toPath().root?.toString()?.lowercase()
    val newSubprojectBuildDir: Directory =
        if (
            projectRoot != null &&
            sharedBuildRoot != null &&
            projectRoot != sharedBuildRoot
        ) {
            project.layout.projectDirectory.dir("build")
        } else {
            newBuildDir.dir(project.name)
        }
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
