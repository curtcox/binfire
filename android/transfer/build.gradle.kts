plugins {
    id("org.jetbrains.kotlin.jvm")
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation(project(":core"))
    implementation("org.json:json:20250517")
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    systemProperty("binfire.fixtures", rootDir.resolve("../shared/fixtures").absolutePath)
}
