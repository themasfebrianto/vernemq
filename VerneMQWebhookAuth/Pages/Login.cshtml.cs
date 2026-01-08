using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace VerneMQWebhookAuth.Pages;

public class LoginModel : PageModel
{
    public string? ReturnUrl { get; set; }

    public void OnGet(string? returnUrl = null)
    {
        // If already authenticated, redirect to dashboard
        if (User.Identity?.IsAuthenticated == true)
        {
            Response.Redirect("/Index");
            return;
        }
        
        ReturnUrl = returnUrl ?? "/Index";
    }
}
