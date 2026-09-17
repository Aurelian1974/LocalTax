// Architecture tests driven by .ai/architecture/profile.yml
// Packages: xunit, NetArchTest.Rules, YamlDotNet
using System.Diagnostics.CodeAnalysis;
using System.Reflection;
using System.Reflection.Emit;
using NetArchTest.Rules;
using Xunit;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

namespace LocalTax.ArchitectureTests;

public sealed class ProfileFixture
{
    public Profile Profile { get; }
    public ProfileFixture()
    {
        var path = Path.Combine(SolutionRoot(), ".ai", "architecture", "profile.yml");
        Profile = new DeserializerBuilder().WithNamingConvention(UnderscoredNamingConvention.Instance)
            .IgnoreUnmatchedProperties().Build().Deserialize<Profile>(File.ReadAllText(path));
    }
    private static string SolutionRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, ".ai", "architecture", "profile.yml"))) dir = dir.Parent;
        return dir?.FullName ?? throw new InvalidOperationException("Repository root not found.");
    }
}

public sealed class Profile
{
    public SystemSection System { get; set; } = new();
    public List<ModuleSection> Modules { get; set; } = [];
    public sealed class SystemSection { public string RootNamespace { get; set; } = ""; public string Topology { get; set; } = ""; }
    public sealed class ModuleSection
    {
        public string Name { get; set; } = "";
        public string Recipe { get; set; } = "";
        public List<string> Consumes { get; set; } = [];
    }
}

public sealed class ModuleBoundaryTests(ProfileFixture fx) : IClassFixture<ProfileFixture>
{
    private string Root => fx.Profile.System.RootNamespace;

    [Fact(DisplayName = "R-001 Modules reference other modules only through Contracts")]
    public void Modules_do_not_reference_other_module_internals()
    {
        var failures = new List<string>();
        foreach (var a in fx.Profile.Modules)
        foreach (var b in fx.Profile.Modules.Where(m => m.Name != a.Name))
        {
            var result = Types.InAssemblies(ModuleAssemblies(a.Name))
                .ShouldNot().HaveDependencyOnAny(InternalNamespaces(b.Name))
                .GetResult();
            if (!result.IsSuccessful)
                failures.AddRange(result.FailingTypeNames.Select(t => $"{t} → {b.Name} internals"));
        }
        Assert.True(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }

    [Fact(DisplayName = "R-003 Contracts depend only on SharedKernel and BCL")]
    public void Contracts_are_pure()
    {
        foreach (var m in fx.Profile.Modules)
        {
            var contracts = LoadOrNull($"{Root}.Modules.{m.Name}.Contracts");
            if (contracts is null) continue;
            var result = Types.InAssembly(contracts).ShouldNot()
                .HaveDependencyOnAny($"{Root}.Modules.{m.Name}.Domain", $"{Root}.Modules.{m.Name}.Application",
                                     $"{Root}.Modules.{m.Name}.Infrastructure", "Microsoft.EntityFrameworkCore",
                                     "Microsoft.AspNetCore", "Dapper")
                .GetResult();
            Assert.True(result.IsSuccessful, $"{m.Name}.Contracts: {string.Join(", ", result.FailingTypeNames ?? [])}");
        }
    }

    [Fact(DisplayName = "R-004 Domain is persistence- and delivery-ignorant (domain-model recipes)")]
    public void Domain_purity()
    {
        foreach (var m in fx.Profile.Modules.Where(x => x.Recipe is "clean-sliced" or "sliced-domain"))
        {
            var domainNs = $"{Root}.Modules.{m.Name}.Domain";
            var result = Types.InAssemblies(ModuleAssemblies(m.Name)).That().ResideInNamespace(domainNs)
                .ShouldNot().HaveDependencyOnAny("Microsoft.EntityFrameworkCore", "Microsoft.AspNetCore", "Dapper",
                    $"{Root}.Modules.{m.Name}.Application", $"{Root}.Modules.{m.Name}.Infrastructure", $"{Root}.Modules.{m.Name}.Features")
                .GetResult();
            Assert.True(result.IsSuccessful, $"{m.Name}.Domain: {string.Join(", ", result.FailingTypeNames ?? [])}");
        }
    }

    [Fact(DisplayName = "Slices do not depend on other slices' handlers")]
    public void Slices_are_isolated()
    {
        foreach (var m in fx.Profile.Modules)
        {
            var handlers = Types.InAssemblies(ModuleAssemblies(m.Name)).That().HaveNameEndingWith("Handler").GetTypes().ToList();
            foreach (var h in handlers)
            {
                if (h.FullName is null || h.Namespace is null) continue;
                var others = handlers
                    .Where(o => o.Namespace != h.Namespace && o.FullName is not null)
                    .Select(o => o.FullName!)
                    .OfType<string>()
                    .ToArray();
                if (others.Length == 0) continue;
                var result = Types.InAssemblies(ModuleAssemblies(m.Name)).That().ResideInNamespace(h.Namespace)
                    .ShouldNot().HaveDependencyOnAny(others).GetResult();
                Assert.True(result.IsSuccessful, $"{h.Namespace} depends on another slice: {string.Join(", ", result.FailingTypeNames ?? [])}");
            }
        }
    }

    [Fact(DisplayName = "No mediator library when request_dispatch is direct")]
    public void No_mediator() =>
        Assert.True(Types.InAssemblies(fx.Profile.Modules.SelectMany(m => ModuleAssemblies(m.Name)))
            .ShouldNot().HaveDependencyOnAny("MediatR", "Mediator").GetResult().IsSuccessful);

    [Fact(DisplayName = "R-005 EF Core is referenced only by the Migrations project")]
    public void EF_Core_only_in_Migrations()
    {
        var offenders = AllModuleAssemblies()
            .Where(a => a.GetName().Name is { } name && !name.Contains("Migrations", StringComparison.OrdinalIgnoreCase))
            .Where(a => a.GetReferencedAssemblies().Any(r =>
                r.Name is not null &&
                (r.Name.Equals("Microsoft.EntityFrameworkCore", StringComparison.OrdinalIgnoreCase) ||
                 r.Name.StartsWith("Microsoft.EntityFrameworkCore.", StringComparison.OrdinalIgnoreCase))))
            .Select(a => a.GetName().Name)
            .OfType<string>()
            .ToList();
        Assert.True(offenders.Count == 0, string.Join(Environment.NewLine, offenders.Select(n => $"{n} references EF Core")));
    }

    [Fact(DisplayName = "R-007 No DateTime.Now or UtcNow in module code")]
    public void No_DateTime_Now_in_modules()
    {
        var offenders = FindCalls(AllModuleAssemblies(), mb =>
            mb.DeclaringType?.FullName == "System.DateTime" &&
            (mb.Name == "get_Now" || mb.Name == "get_UtcNow")).ToList();
        Assert.True(offenders.Count == 0, string.Join(Environment.NewLine, offenders));
    }

    [Fact(DisplayName = "R-008 Money exists in SharedKernel and rounding lives only in SharedKernel")]
    public void Money_and_rounding_rules()
    {
        var sharedKernel = LoadOrNull($"{Root}.SharedKernel");
        var money = sharedKernel?.GetType($"{Root}.Money") ?? sharedKernel?.GetType($"{Root}.SharedKernel.Money");
        Assert.True(money is not null, $"Money type not found in {Root}.SharedKernel");

        var moduleAssemblies = AllModuleAssemblies();
        var offenders = FindCalls(moduleAssemblies, mb =>
            mb.DeclaringType?.FullName == "System.Math" && mb.Name == "Round").ToList();
        Assert.True(offenders.Count == 0, string.Join(Environment.NewLine, offenders));
    }

    // ── helpers ───────────────────────────────────────────────────────────────
    private IEnumerable<Assembly> ModuleAssemblies(string module) =>
        AppDomain.CurrentDomain.GetAssemblies().Concat(LoadAllFromBin())
            .Where(a => a.GetName().Name is { } n && n.StartsWith($"{Root}.Modules.{module}") && !n.EndsWith(".Contracts") && !n.Contains("Tests"))
            .DistinctBy(a => a.FullName);

    private string[] InternalNamespaces(string module) =>
        [$"{Root}.Modules.{module}.Domain", $"{Root}.Modules.{module}.Application", $"{Root}.Modules.{module}.Infrastructure", $"{Root}.Modules.{module}.Features"];

    private static Assembly? LoadOrNull(string name)
    {
        try { return Assembly.Load(name); }
        catch (FileNotFoundException) { return null; }
        catch (BadImageFormatException) { return null; }
        catch (FileLoadException) { return null; }
    }

    private static IEnumerable<Assembly> LoadAllFromBin() =>
        Directory.EnumerateFiles(AppContext.BaseDirectory, "*.dll").Select(f =>
        {
            try { return Assembly.LoadFrom(f); }
            catch (BadImageFormatException) { return null; }
            catch (FileLoadException) { return null; }
        }).OfType<Assembly>();

    private IEnumerable<Assembly> AllModuleAssemblies() =>
        fx.Profile.Modules.SelectMany(m => ModuleAssemblies(m.Name)).DistinctBy(a => a.FullName);

    private static IEnumerable<string> FindCalls(IEnumerable<Assembly> assemblies, Func<MethodBase, bool> predicate)
    {
        foreach (var asm in assemblies.DistinctBy(a => a.FullName))
        foreach (var type in GetLoadableTypes(asm))
        foreach (var method in DeclaredMethodsAndConstructors(type))
        {
            var body = method.GetMethodBody();
            var il = body?.GetILAsByteArray();
            if (il is null) continue;
            for (int i = 0; i < il.Length;)
            {
                (var op, int opSize) = ReadOpCode(il, i);
                i += opSize;
                int operandSize = GetOperandSize(op, il, i);
                if (IsCall(op) && operandSize == 4)
                {
                    var token = BitConverter.ToInt32(il, i);
                    if (TryResolveCall(method, type, token, predicate, out var call))
                        yield return call;
                }
                i += operandSize;
            }
        }
    }

    private static IEnumerable<MethodBase> DeclaredMethodsAndConstructors(Type type)
    {
        const BindingFlags flags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance | BindingFlags.DeclaredOnly;
        return type.GetMethods(flags).Concat(type.GetConstructors(flags).Cast<MethodBase>());
    }

    private static (OpCode Op, int Size) ReadOpCode(byte[] il, int offset)
    {
        if (il[offset] == 0xFE && offset + 1 < il.Length)
            return (TwoByteOpCodes[il[offset + 1]], 2);
        return (OneByteOpCodes[il[offset]], 1);
    }

    private static int GetOperandSize(OpCode op, byte[] il, int operandOffset) => op.OperandType switch
    {
        OperandType.InlineNone => 0,
        OperandType.ShortInlineI or OperandType.ShortInlineVar or OperandType.ShortInlineBrTarget => 1,
        OperandType.InlineVar => 2,
        OperandType.InlineBrTarget or OperandType.InlineField or OperandType.InlineI or OperandType.InlineMethod or OperandType.InlineSig or OperandType.InlineString or OperandType.InlineTok or OperandType.InlineType or OperandType.ShortInlineR => 4,
        OperandType.InlineI8 or OperandType.InlineR => 8,
        OperandType.InlineSwitch => 4 + BitConverter.ToInt32(il, operandOffset) * 4,
        _ => 0
    };

    private static bool IsCall(OpCode op) => op == OpCodes.Call || op == OpCodes.Callvirt;

    private static bool TryResolveCall(MethodBase method, Type type, int token, Func<MethodBase, bool> predicate, [NotNullWhen(true)] out string? call)
    {
        call = null;
        try
        {
            var typeArgs = type.IsGenericType ? type.GetGenericArguments() : null;
            var methodArgs = method.IsGenericMethod ? method.GetGenericArguments() : null;
            var mb = method.Module.ResolveMethod(token, typeArgs, methodArgs);
            if (mb is null || !predicate(mb)) return false;
            call = $"{(type.FullName ?? type.Name)}.{method.Name} -> {mb.DeclaringType?.FullName}.{mb.Name}";
            return true;
        }
        // Unresolvable metadata tokens are expected for generic/forwarded methods; we only care about calls we can resolve.
        catch (ArgumentException) { return false; }
        catch (BadImageFormatException) { return false; }
    }

    private static IEnumerable<Type> GetLoadableTypes(Assembly asm)
    {
        try { return asm.GetTypes(); }
        catch (ReflectionTypeLoadException ex) { return ex.Types.OfType<Type>(); }
    }

    private static readonly Dictionary<byte, OpCode> OneByteOpCodes = typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static)
        .Where(f => f.FieldType == typeof(OpCode))
        .Select(f => (OpCode)(f.GetValue(null) ?? throw new InvalidOperationException("OpCode field cannot be null.")))
        .Where(o => o.Size == 1)
        .ToDictionary(o => (byte)o.Value);
    private static readonly Dictionary<byte, OpCode> TwoByteOpCodes = typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static)
        .Where(f => f.FieldType == typeof(OpCode))
        .Select(f => (OpCode)(f.GetValue(null) ?? throw new InvalidOperationException("OpCode field cannot be null.")))
        .Where(o => o.Size == 2)
        .ToDictionary(o => (byte)(o.Value & 0xFF));
}
