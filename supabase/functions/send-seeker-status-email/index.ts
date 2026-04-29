import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Payload = {
  applicationId?: string;
  applicantUserId?: string;
  applicantEmail?: string;
  applicantName?: string;
  jobId?: string;
  newStatus?: string;
  statusUpdatedAt?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

const STATUS_LABELS: Record<string, string> = {
  viewed: "Viewed",
  reviewed: "Reviewed",
  future_consideration: "Future Consideration",
  interested: "Interested",
  rejected: "Not Moving Forward",
  pending: "Pending",
  applied: "Applied",
};

function friendlyStatus(status: string): string {
  return STATUS_LABELS[status.toLowerCase()] ?? status;
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
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const applicationId = payload.applicationId?.trim() ?? "";
    const applicantUserId = payload.applicantUserId?.trim() ?? "";
    const jobId = payload.jobId?.trim() ?? "";
    const newStatus = payload.newStatus?.trim().toLowerCase() ?? "";
    const statusUpdatedAt = payload.statusUpdatedAt?.trim() ?? "";

    if (!applicationId || !jobId) {
      return new Response(JSON.stringify({ error: "Missing required fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);

    // Look up the seeker's notification preference if we have a user id.
    let notifyEnabled = true;
    let seekerEmail = payload.applicantEmail?.trim() ?? "";

    if (applicantUserId) {
      const { data: seekerRow } = await admin
        .from("job_seeker_profiles")
        .select("email, notify_on_application_status_change")
        .eq("user_id", applicantUserId)
        .maybeSingle();

      if (seekerRow) {
        notifyEnabled =
          seekerRow.notify_on_application_status_change !== false;
        // Prefer profile email over what was passed in the payload.
        if (seekerRow.email?.trim()) {
          seekerEmail = seekerRow.email.trim();
        }
      }
    }

    if (!notifyEnabled) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "Seeker notification preference disabled" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!seekerEmail) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "No seeker email available" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Look up the job title for the email body.
    const { data: jobRow } = await admin
      .from("job_listings")
      .select("title, company")
      .eq("id", jobId)
      .maybeSingle();

    const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
    const emailFrom = Deno.env.get("EMAIL_FROM") ?? "";

    if (!resendApiKey || !emailFrom) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "RESEND_API_KEY or EMAIL_FROM is not configured" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const applicantName = payload.applicantName?.trim() || "Applicant";
    const jobTitle = (jobRow?.title as string | null)?.trim() || "your application";
    const companyName = (jobRow?.company as string | null)?.trim() || "the company";
    const statusLabel = friendlyStatus(newStatus);
    const statusDateLabel = statusUpdatedAt
      ? (() => {
          const parsed = new Date(statusUpdatedAt);
          return Number.isNaN(parsed.getTime())
            ? statusUpdatedAt
            : parsed.toLocaleString("en-US", {
                year: "numeric",
                month: "short",
                day: "numeric",
                hour: "numeric",
                minute: "2-digit",
              });
        })()
      : null;

    const subject = `Application update: ${jobTitle} at ${companyName}`;
    const html = `
      <h2>Application Status Update</h2>
      <p>Hi ${applicantName},</p>
      <p>Your application for <strong>${jobTitle}</strong> at <strong>${companyName}</strong> has been updated.</p>
      <p><strong>New Status:</strong> ${statusLabel}</p>
      ${statusDateLabel ? `<p><strong>Updated:</strong> ${statusDateLabel}</p>` : ""}
      <p><strong>Application ID:</strong> ${applicationId}</p>
      <p style="color: #666; font-size: 13px; margin-top: 24px;">
        You are receiving this email because you have application status notifications enabled in your job seeker profile.
        You can turn these off in your profile settings.
      </p>
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
          to: [seekerEmail],
          subject,
          html,
        }),
      });
    } catch (error) {
      return new Response(
        JSON.stringify({ error: `Email provider request failed: ${String(error)}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!resendResponse.ok) {
      const body = await resendResponse.text();
      return new Response(
        JSON.stringify({ error: `Resend failed: ${body}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: `Unhandled function error: ${String(error)}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
