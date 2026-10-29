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

subprojects {
    // home_widget 0.8.1 自身 jvmTarget=1.8, 但其依赖 glance 是 JVM 11 字节码 → 内联报错。
    // Kotlin 2.x 会校验 Java/Kotlin target 一致 → Java compileOptions 一起抬到 17。
    // :app 已被 evaluationDependsOn 提前评估, afterEvaluate 会炸 → 按状态分流。
    val raiseJvmTarget: Project.() -> Unit = {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
            .configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.BaseExtension> {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
    }
    if (project.state.executed) project.raiseJvmTarget()
    else project.afterEvaluate(raiseJvmTarget)
    // home_widget 用动态版本 glance-appwidget:1.+, 会拉到 1.3.0-alpha
    // (要求 compileSdk 37 / AGP 9.1) → 锁到稳定版 1.1.1。
    configurations.all {
        resolutionStrategy {
            force("androidx.glance:glance-appwidget:1.1.1")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
