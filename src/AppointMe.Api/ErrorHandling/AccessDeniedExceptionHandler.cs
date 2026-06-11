namespace AppointMe.Api.ErrorHandling;

using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Shared.Domain.Errors;

internal sealed class AccessDeniedExceptionHandler(
    IProblemDetailsService problemDetailsService,
    ILogger<AccessDeniedExceptionHandler> logger
) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception,
        CancellationToken cancellationToken)
    {
        if (exception is not AccessDeniedException accessDeniedException)
        {
            return false;
        }

        logger.LogWarning(exception, "Unhandled access denied exception occurred");

        httpContext.Response.StatusCode = StatusCodes.Status403Forbidden;
        var context = new ProblemDetailsContext
        {
            HttpContext = httpContext,
            Exception = exception,
            ProblemDetails = new ProblemDetails
            {
                Title = "Access denied",
                Detail = accessDeniedException.Message,
                Status = StatusCodes.Status403Forbidden
            }
        };

        return await problemDetailsService.TryWriteAsync(context);
    }
}
