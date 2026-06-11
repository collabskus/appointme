namespace AppointMe.Booking.Tests.Appointments;

public class AppointmentDtoEnricherTests
{
    private static AppointmentDto NewDto(
        string? providerFirstName,
        string? providerLastName,
        string? attendeeFirstName,
        string? attendeeLastName) => new()
        {
            Id = NewId(),
            Start = DateTimeOffset.UtcNow,
            End = DateTimeOffset.UtcNow.AddHours(1),
            Status = AppointmentStatus.Scheduled,
            ProviderId = NewId(),
            ProviderFirstName = providerFirstName,
            ProviderLastName = providerLastName,
            AttendeeId = NewId(),
            AttendeeFirstName = attendeeFirstName,
            AttendeeLastName = attendeeLastName,
            ScheduledAt = DateTimeOffset.UtcNow
        };

    [Fact]
    public void should_enrich_full_name_and_initials_for_both_provider_and_attendee_when_names_are_present()
    {
        var dto = NewDto("Alex", "Stone", "Jane", "Doe");

        var enriched = dto.Enrich();

        Assert.Equal("Alex Stone", enriched.ProviderName);
        Assert.Equal("AS", enriched.ProviderInitials);
        Assert.Equal("Jane Doe", enriched.AttendeeName);
        Assert.Equal("JD", enriched.AttendeeInitials);
    }

    [Fact]
    public void should_leave_provider_name_and_initials_null_when_provider_first_name_is_missing()
    {
        var dto = NewDto(providerFirstName: null, providerLastName: "Stone", attendeeFirstName: "Jane", attendeeLastName: "Doe");

        var enriched = dto.Enrich();

        Assert.Null(enriched.ProviderName);
        Assert.Null(enriched.ProviderInitials);
        Assert.Equal("Jane Doe", enriched.AttendeeName);
        Assert.Equal("JD", enriched.AttendeeInitials);
    }

    [Fact]
    public void should_compose_provider_name_without_last_name_when_last_name_is_missing()
    {
        var dto = NewDto(providerFirstName: "Alex", providerLastName: null, attendeeFirstName: "Jane", attendeeLastName: "Doe");

        var enriched = dto.Enrich();

        Assert.Equal("Alex", enriched.ProviderName);
        Assert.Equal("A", enriched.ProviderInitials);
    }

    [Fact]
    public void should_enrich_each_party_independently_when_only_one_is_known()
    {
        var dto = NewDto(providerFirstName: "Alex", providerLastName: "Stone", attendeeFirstName: null, attendeeLastName: null);

        var enriched = dto.Enrich();

        Assert.Equal("Alex Stone", enriched.ProviderName);
        Assert.Equal("AS", enriched.ProviderInitials);
        Assert.Null(enriched.AttendeeName);
        Assert.Null(enriched.AttendeeInitials);
    }
}
