plugins {
    id("org.jetbrains.kotlin.jvm")
}

kotlin { jvmToolchain(17) }

// No JSON library: core has its own strict JSON reader (app.binfire.core.Json)
// because the specs require JSON.parse semantics, which org.json does not have.
// This also avoids clashing with the org.json copy inside Android itself.
dependencies {
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    // Conformance fixtures live in the repository root.
    systemProperty("binfire.fixtures", rootDir.resolve("../shared/fixtures").absolutePath)
    systemProperty("binfire.registry", rootDir.resolve("../shared/registry/apps.json").absolutePath)
    systemProperty("binfire.config", rootDir.resolve("../config/binfire.config.json").absolutePath)
    systemProperty("binfire.assets", rootDir.resolve("app/src/main/assets/binfire").absolutePath)
}
