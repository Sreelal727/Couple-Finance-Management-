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
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some third-party plugins still declare an old Kotlin JVM target (another_telephony
// targets 1.8) while AGP compiles their Java sources for a newer JVM, and Kotlin 2.x
// refuses that mismatch. Align every plugin module with the app: Java and Kotlin 17.
subprojects {
    val alignJavaTarget: Project.() -> Unit = {
        extensions.findByType(com.android.build.api.dsl.CommonExtension::class.java)?.apply {
            compileOptions.sourceCompatibility = JavaVersion.VERSION_17
            compileOptions.targetCompatibility = JavaVersion.VERSION_17
        }
    }
    // :app is already evaluated here because of evaluationDependsOn above.
    if (state.executed) alignJavaTarget() else afterEvaluate { alignJavaTarget() }
}
gradle.projectsEvaluated {
    subprojects {
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
