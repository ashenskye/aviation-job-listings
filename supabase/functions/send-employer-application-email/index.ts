import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Payload = {
  test?: boolean;
  applicationId?: string;
  employerId?: string;
  jobId?: string;
  status?: string;
  matchPercentage?: number;
  applicantName?: string;
  applicantEmail?: string;
  applicantCity?: string;
  applicantStateOrProvince?: string;
  appliedAt?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

function looksLikeMissingColumnError(message: string): boolean {
  const text = message.toLowerCase();
  return text.includes("column") &&
    (text.includes("does not exist") || text.includes("schema cache"));
}

serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "Supabase env not configured" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let payload: Payload;
    try {
      payload = (await req.json()) as Payload;
    } catch (_) {
      return new Response(
        JSON.stringify({ error: "Invalid JSON body" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const isTest = payload.test === true;
    const applicationId = payload.applicationId?.trim() ?? "";
    const employerId = payload.employerId?.trim() ?? "";
    const jobId = payload.jobId?.trim() ?? "";
    const status = payload.status?.trim().toLowerCase() ?? "";

    if (!employerId) {
      return new Response(JSON.stringify({ error: "Missing employerId" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!isTest && (!applicationId || !jobId)) {
      return new Response(JSON.stringify({ error: "Missing required fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Guardrail: only notify for non-rejected applications.
    if (!isTest && status === "rejected") {
      return new Response(
        JSON.stringify({ skipped: true, reason: "Rejected applications do not notify" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);

    let employerRow:
      | {
          company_name: string | null;
          contact_email: string | null;
          notify_on_new_non_rejected_application?: boolean | null;
        }
      | null = null;

    const employerWithPref = await admin
      .from("employer_profiles")
      .select(
        "company_name, contact_email, notify_on_new_non_rejected_application",
      )
      .eq("id", employerId)
      .maybeSingle();

    if (employerWithPref.error &&
      looksLikeMissingColumnError(employerWithPref.error.message)) {
      const employerFallback = await admin
        .from("employer_profiles")
        .select("company_name, contact_email")
        .eq("id", employerId)
        .maybeSingle();

      if (employerFallback.error) {
        return new Response(
          JSON.stringify({ error: `Failed to load employer: ${employerFallback.error.message}` }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      employerRow = employerFallback.data;
    } else if (employerWithPref.error) {
      return new Response(
        JSON.stringify({ error: `Failed to load employer: ${employerWithPref.error.message}` }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    } else {
      employerRow = employerWithPref.data;
    }

    const notifyEnabled =
      employerRow?.notify_on_new_non_rejected_application ?? true;
    if (!notifyEnabled) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "Employer preference disabled" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const toEmail = (employerRow?.contact_email as string | null)?.trim() ?? "";
    if (!toEmail) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "No employer contact email set" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: jobRow } = isTest
      ? { data: null }
      : await admin
          .from("job_listings")
          .select("title, company")
          .eq("id", jobId)
          .maybeSingle();

    const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
    const emailFrom = Deno.env.get("EMAIL_FROM") ?? "";

    if (!resendApiKey || !emailFrom) {
      return new Response(
        JSON.stringify({
          skipped: true,
          reason: "RESEND_API_KEY or EMAIL_FROM is not configured",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const applicantName = payload.applicantName?.trim() || "New applicant";
    const applicantEmail = payload.applicantEmail?.trim() || "Not provided";
    const applicantLocation = [
      payload.applicantCity?.trim() || "",
      payload.applicantStateOrProvince?.trim() || "",
    ].filter((part) => part.length > 0).join(", ") || "Not provided";

    const match = Number.isFinite(payload.matchPercentage)
      ? payload.matchPercentage
      : 0;

    const jobTitle = (jobRow?.title as string | null)?.trim() || "your listing";
    const companyName =
      (jobRow?.company as string | null)?.trim() ||
      (employerRow?.company_name as string | null)?.trim() ||
      "your company";

    const subject = isTest
      ? `Test notification for ${companyName}`
      : `New application for ${jobTitle}`;
    const html = `
    <h2>${isTest ? "Test Notification" : "New Application Received"}</h2>
    <p><strong>Company:</strong> ${companyName}</p>
    ${isTest ? "<p>This is a test email from your Employer Notification Preferences.</p>" : `<p><strong>Listing:</strong> ${jobTitle}</p>
    <p><strong>Applicant:</strong> ${applicantName}</p>
    <p><strong>Email:</strong> ${applicantEmail}</p>
    <p><strong>Location:</strong> ${applicantLocation}</p>
    <p><strong>Match Score:</strong> ${match}%</p>
    <p><strong>Application ID:</strong> ${applicationId}</p>
    <p>This notification was sent because \"Email on new non-rejected applications\" is enabled in your employer profile.</p>`}
  `;

    let resendResponse: Response;
    try {
      resendResponse = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: emailFrom,
          to: [toEmail],
          subject,
          html,
        }),
      });
    } catch (error) {
      return new Response(
        JSON.stringify({ error: `Email provider request failed: ${String(error)}` }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!resendResponse.ok) {
      const body = await resendResponse.text();

      // Test mode fallback: allow end-to-end verification before domain setup.
      if (
        isTest &&
        body.toLowerCase().includes("domain is not verified")
      ) {
        const fallbackFrom = "onboarding@resend.dev";
        const fallbackResponse = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${resendApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from: fallbackFrom,
            to: [toEmail],
            subject,
            html,
          }),
        });

        if (fallbackResponse.ok) {
          return new Response(
            JSON.stringify({
              success: true,
              warning:
                "Test email sent via onboarding@resend.dev fallback. Configure a verified EMAIL_FROM domain for production.",
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }

        const fallbackBody = await fallbackResponse.text();
        return new Response(
          JSON.stringify({ error: `Resend fallback failed: ${fallbackBody}` }),
          {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      return new Response(
        JSON.stringify({ error: `Resend failed: ${body}` }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: `Unhandled function error: ${String(error)}` }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
