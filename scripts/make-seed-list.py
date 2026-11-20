#!/usr/bin/env python3
"""Generate seed/packages.txt: a fixed list of real public packages from nuget.org.

Run once; the output is committed and then treated as fixed. Picks, for each
package ID below, up to 3 stable SemVer1 versions (the latest stable plus older
ones spread across its history), skipping any nupkg over MAX_BYTES and any
version whose nuspec makes it SemVer2 (build metadata, or a dependency range
that uses a prerelease or build-metadata version), because the gallery's
package-ids and package-versions endpoints hide SemVer2 by default.

Output lines: "<Id> <normalized-version>", grouped by family, sorted.
"""
import json, re, sys, urllib.request, xml.etree.ElementTree as ET

FLAT = "https://api.nuget.org/v3-flatcontainer"
MAX_BYTES = 4 * 1024 * 1024
VERSIONS_PER_ID = 3

# Families share a prefix so the package-ids prefix checks mean something.
FAMILIES = {
    "Serilog": ["Serilog", "Serilog.AspNetCore", "Serilog.Enrichers.Environment", "Serilog.Enrichers.Thread",
                "Serilog.Enrichers.Process", "Serilog.Extensions.Hosting", "Serilog.Extensions.Logging",
                "Serilog.Formatting.Compact", "Serilog.Settings.Configuration", "Serilog.Sinks.Async",
                "Serilog.Sinks.Console", "Serilog.Sinks.Debug", "Serilog.Sinks.File",
                "Serilog.Sinks.PeriodicBatching", "Serilog.Sinks.Seq", "Serilog.Exceptions"],
    "Newtonsoft": ["Newtonsoft.Json", "Newtonsoft.Json.Bson", "Newtonsoft.Json.Schema"],
    "xunit": ["xunit", "xunit.abstractions", "xunit.analyzers", "xunit.assert", "xunit.core",
              "xunit.extensibility.core", "xunit.extensibility.execution", "xunit.runner.console",
              "xunit.runner.visualstudio"],
    "NUnit": ["NUnit", "NUnit3TestAdapter", "NUnit.Analyzers", "NUnitLite"],
    "Polly": ["Polly", "Polly.Core", "Polly.Extensions", "Polly.Extensions.Http", "Polly.Contrib.WaitAndRetry",
              "Polly.RateLimiting"],
    "AutoMapper": ["AutoMapper", "AutoMapper.Collection", "AutoMapper.Extensions.Microsoft.DependencyInjection"],
    "Fluent": ["FluentValidation", "FluentValidation.AspNetCore", "FluentValidation.DependencyInjectionExtensions",
               "FluentAssertions", "FluentMigrator", "FluentMigrator.Runner"],
    "Dapper": ["Dapper", "Dapper.Contrib", "Dapper.SqlBuilder"],
    "MediatR": ["MediatR", "MediatR.Contracts", "MediatR.Extensions.Microsoft.DependencyInjection"],
    "Moq": ["Moq", "Moq.AutoMock"],
    "Humanizer": ["Humanizer.Core", "Humanizer.Core.fr", "Humanizer.Core.de", "Humanizer.Core.ja"],
    "NodaTime": ["NodaTime", "NodaTime.Serialization.JsonNet", "NodaTime.Testing"],
    "CsvHelper": ["CsvHelper"],
    "RestSharp": ["RestSharp", "RestSharp.Serializers.NewtonsoftJson"],
    "StackExchange": ["StackExchange.Redis"],
    "Castle": ["Castle.Core", "Castle.Windsor"],
    "Autofac": ["Autofac", "Autofac.Extensions.DependencyInjection", "Autofac.Mvc5", "Autofac.WebApi2"],
    "Microsoft.Extensions.Logging": [
        "Microsoft.Extensions.Logging", "Microsoft.Extensions.Logging.Abstractions",
        "Microsoft.Extensions.Logging.Configuration", "Microsoft.Extensions.Logging.Console",
        "Microsoft.Extensions.Logging.Debug", "Microsoft.Extensions.Logging.EventLog",
        "Microsoft.Extensions.Logging.EventSource", "Microsoft.Extensions.Logging.TraceSource"],
    "Microsoft.Extensions.Configuration": [
        "Microsoft.Extensions.Configuration", "Microsoft.Extensions.Configuration.Abstractions",
        "Microsoft.Extensions.Configuration.Binder", "Microsoft.Extensions.Configuration.CommandLine",
        "Microsoft.Extensions.Configuration.EnvironmentVariables", "Microsoft.Extensions.Configuration.FileExtensions",
        "Microsoft.Extensions.Configuration.Json", "Microsoft.Extensions.Configuration.UserSecrets",
        "Microsoft.Extensions.Configuration.Xml", "Microsoft.Extensions.Configuration.Ini"],
    "Microsoft.Extensions.DependencyInjection": [
        "Microsoft.Extensions.DependencyInjection", "Microsoft.Extensions.DependencyInjection.Abstractions"],
    "Microsoft.Extensions.Primitives": ["Microsoft.Extensions.Primitives"],
    "System.Collections": ["System.Collections", "System.Collections.Concurrent", "System.Collections.Immutable",
                           "System.Collections.NonGeneric", "System.Collections.Specialized"],
    "System.Text": ["System.Text.Encoding", "System.Text.Encoding.Extensions", "System.Text.Encodings.Web",
                    "System.Text.Json", "System.Text.RegularExpressions"],
    "System.Memory": ["System.Memory", "System.Buffers", "System.Numerics.Vectors",
                      "System.Runtime.CompilerServices.Unsafe", "System.Threading.Tasks.Extensions"],
    "misc": ["Bogus", "Swashbuckle.AspNetCore", "Swashbuckle.AspNetCore.Swagger", "Swashbuckle.AspNetCore.SwaggerGen",
             "Swashbuckle.AspNetCore.SwaggerUI", "HtmlAgilityPack", "Hangfire.Core", "Hangfire.SqlServer",
             "Quartz", "Quartz.Extensions.Hosting", "YamlDotNet", "SharpZipLib", "DotNetZip", "log4net", "NLog",
             "NLog.Extensions.Logging", "NLog.Web.AspNetCore", "Spectre.Console", "CommandLineParser",
             "MimeKit", "MailKit", "BouncyCastle.Cryptography", "Ardalis.GuardClauses", "Ardalis.Specification",
             "OneOf", "Scrutor", "Refit", "Refit.HttpClientFactory", "Nito.AsyncEx", "Nito.AsyncEx.Coordination",
             "Nito.Disposables", "Ninject", "Unity", "SimpleInjector", "Shouldly", "NSubstitute",
             "AutoFixture", "AutoFixture.Xunit2", "AutoFixture.AutoMoq", "Stateless", "Polly.Caching.Memory"],
}

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "nuget-harness-seed-list"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()

def head_len(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "nuget-harness-seed-list"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return int(r.headers.get("Content-Length", "0"))

def is_semver2_version(v):
    v = v.strip()
    if "+" in v:
        return True
    if "-" in v:
        label = v.split("-", 1)[1]
        return "." in label
    return False

def nuspec_is_semver2(xml_bytes):
    root = ET.fromstring(xml_bytes)
    for el in root.iter():
        tag = el.tag.split("}")[-1]
        if tag == "version" and el.text and is_semver2_version(el.text):
            return True
        if tag == "dependency":
            rng = el.attrib.get("version", "")
            for part in re.split(r"[\[\]\(\),]", rng):
                part = part.strip()
                if part and ("+" in part or "-" in part):
                    return True  # prerelease or metadata dependency: treat as excluded to be safe
    return False

def pick(versions):
    stable = [v for v in versions if "-" not in v and "+" not in v]
    if not stable:
        return []
    chosen = [stable[-1]]
    if len(stable) > 1:
        chosen.append(stable[0 if len(stable) < 4 else len(stable) // 2])
    if len(stable) > 3:
        chosen.append(stable[len(stable) * 3 // 4])
    out = []
    for v in chosen:
        if v not in out:
            out.append(v)
    return out[:VERSIONS_PER_ID]

def main():
    lines = []
    for family, ids in FAMILIES.items():
        lines.append(f"# {family}")
        for pid in ids:
            low = pid.lower()
            try:
                versions = json.loads(get(f"{FLAT}/{low}/index.json"))["versions"]
            except Exception as e:
                print(f"skip {pid}: {e}", file=sys.stderr)
                continue
            kept = 0
            for v in reversed(pick(versions)):
                base = f"{FLAT}/{low}/{v}"
                size = head_len(f"{base}/{low}.{v}.nupkg")
                if size > MAX_BYTES:
                    print(f"skip {pid} {v}: {size} bytes", file=sys.stderr)
                    continue
                if nuspec_is_semver2(get(f"{base}/{low}.nuspec")):
                    print(f"skip {pid} {v}: semver2", file=sys.stderr)
                    continue
                lines.append(f"{pid} {v}")
                kept += 1
            if kept == 0:
                print(f"no versions kept for {pid}", file=sys.stderr)
    with open(sys.argv[1] if len(sys.argv) > 1 else "seed/packages.txt", "w") as f:
        f.write("# Fixed seed list. Format: <Id> <normalized version as used by the nuget.org flat container>.\n")
        f.write("# Generated once by scripts/make-seed-list.py, then committed and kept fixed.\n")
        f.write("\n".join(lines) + "\n")

if __name__ == "__main__":
    main()
