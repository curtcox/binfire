plugins {
    id("org.jetbrains.kotlin.jvm")
}

kotlin { jvmToolchain(17) }

dependencies {
    api(project(":core"))
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    systemProperty("binfire.fixtures", rootDir.resolve("../shared/fixtures").absolutePath)
    systemProperty("binfire.config", rootDir.resolve("../config/binfire.config.json").absolutePath)
}
