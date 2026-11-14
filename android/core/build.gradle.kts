plugins {
    id("org.jetbrains.kotlin.jvm")
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation("org.json:json:20250517")
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    // Conformance fixtures live in the repository root.
    systemProperty("binfire.fixtures", rootDir.resolve("../shared/fixtures").absolutePath)
    systemProperty("binfire.registry", rootDir.resolve("../shared/registry/apps.json").absolutePath)
}
