namespace LocalTax;

public readonly record struct Money : IComparable<Money>
{
    private const int CurrencyScale = 2;

    public decimal Amount { get; }

    private Money(decimal amount)
    {
        Amount = Round(amount);
    }

    public static Money Zero => new(0m);

    public static Money From(decimal amount) => new(amount);

    public static Money operator +(Money left, Money right) => new(left.Amount + right.Amount);

    public static Money operator -(Money left, Money right) => new(left.Amount - right.Amount);

    public static Money operator *(Money left, decimal factor) => new(left.Amount * factor);

    public int CompareTo(Money other) => Amount.CompareTo(other.Amount);

    private static decimal Round(decimal amount) => Math.Round(amount, CurrencyScale, MidpointRounding.AwayFromZero);
}
