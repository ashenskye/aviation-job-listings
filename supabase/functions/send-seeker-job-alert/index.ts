import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * send-seeker-job-alert
 *
 * Designed to be called on a schedule (e.g., daily via Supabase cron or an
 * external scheduler). Queries jobs posted in the last `hoursBack` hours,
 * finds seekers with job alerts enabled, filters by their preferences, and
 * sends a digest email per seeker.
 *
 * Can also be triggered manually or via a database webhook.
 *
 * Query params / body:
 *   hoursBack: number  (default 24) — look-back window for new jobs
 */

type SeekerRow = {
  user_id: string;
  email: string | null;
  state_or_province: string | null;
  airframe_scope: string | null;
  faa_certificates: string[] | null;
  type_ratings: string[] | null;
  flight_hours: Record<string, number> | null;
  flight_hours_types: string[] | null;
  specialty_flight_hours_map: Record<string, number> | null;
  specialty_flight_hours: string[] | null;
  new_job_alert_enabled?: boolean;
  new_job_alert_state_only: boolean;
  new_job_alert_airframe_match: boolean;
  new_job_alert_minimum_match_percent: number | null;
  new_job_alert_certificate_match: boolean;
};

type Payload = {
  test?: boolean;
  seekerUserId?: string;
  hoursBack?: number;
};

type JobRow = {
  id: string;
  title: string;
  company: string;
  location: string | null;
  airframe_scope: string | null;
  faa_certificates: string[] | null;
  required_ratings: string[] | null;
  flight_hours: Record<string, number> | null;
  preferred_flight_hours: string[] | null;
  instructor_hours: Record<string, number> | null;
  preferred_instructor_hours: string[] | null;
  specialty_hours: Record<string, number> | null;
  preferred_specialty_hours: string[] | null;
  status: string | null;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

function airframeCompatible(jobScope: string | null, seekerScope: string | null): boolean {
  if (!jobScope || !seekerScope) return true;
  if (jobScope.toLowerCase() === "both" || seekerScope.toLowerCase() === "both") return true;
  return jobScope.toLowerCase() === seekerScope.toLowerCase();
}

function normalizeLabel(value: string): string {
  return value.trim().toLowerCase();
}

function listContainsLabel(values: string[] | null, target: string): boolean {
  if (!values || values.length === 0) {
    return false;
  }
  const targetLabel = normalizeLabel(target);
  return values.some((value) => normalizeLabel(value) === targetLabel);
}

function mapValue(map: Record<string, number> | null, key: string): number {
  if (!map) {
    return 0;
  }
  const direct = map[key];
  if (typeof direct === "number") {
    return direct;
  }
  const normalized = normalizeLabel(key);
  for (const [mapKey, mapValue] of Object.entries(map)) {
    if (normalizeLabel(mapKey) === normalized && typeof mapValue === "number") {
      return mapValue;
    }
  }
  return 0;
}

function isPreferredHourLabel(preferred: string[] | null, label: string): boolean {
  return listContainsLabel(preferred, label);
}

function evaluateJobMatchPercent(job: JobRow, seeker: SeekerRow): number {
  let matchedCount = 0;
  let totalCount = 0;

  const hoursBlocked = !airframeCompatible(job.airframe_scope, seeker.airframe_scope);
  const seekerCerts = new Set((seeker.faa_certificates ?? []).map((c) => normalizeLabel(c)));
  const seekerRatings = new Set((seeker.type_ratings ?? []).map((r) => normalizeLabel(r)));

  for (const cert of job.faa_certificates ?? []) {
    totalCount++;
    if (seekerCerts.has(normalizeLabel(cert))) {
      matchedCount++;
    }
  }

  for (const rating of job.required_ratings ?? []) {
    totalCount++;
    const normalized = normalizeLabel(rating);
    if (seekerCerts.has(normalized) || seekerRatings.has(normalized)) {
      matchedCount++;
    }
  }

  for (const [label, required] of Object.entries(job.flight_hours ?? {})) {
    if (isPreferredHourLabel(job.preferred_flight_hours, label)) {
      continue;
    }
    totalCount++;
    const profileHours = mapValue(seeker.flight_hours, label);
    const hasType = listContainsLabel(seeker.flight_hours_types, label);
    if (!hoursBlocked && hasType && profileHours >= Number(required)) {
      matchedCount++;
    }
  }

  for (const [label, required] of Object.entries(job.instructor_hours ?? {})) {
    if (isPreferredHourLabel(job.preferred_instructor_hours, label)) {
      continue;
    }
    totalCount++;
    const profileHours = mapValue(seeker.flight_hours, label);
    const hasType = listContainsLabel(seeker.flight_hours_types, label);
    if (!hoursBlocked && hasType && profileHours >= Number(required)) {
      matchedCount++;
    }
  }

  for (const [label, required] of Object.entries(job.specialty_hours ?? {})) {
    if (isPreferredHourLabel(job.preferred_specialty_hours, label)) {
      continue;
    }
    totalCount++;
    const profileHours = mapValue(seeker.specialty_flight_hours_map, label);
    const hasType = listContainsLabel(seeker.specialty_flight_hours, label);
    if (!hoursBlocked && hasType && profileHours >= Number(required)) {
      matchedCount++;
    }
  }

  if (
    job.airframe_scope &&
    seeker.airframe_scope &&
    job.airframe_scope !== "Both" &&
    seeker.airframe_scope !== "Both"
  ) {
    totalCount++;
    if (normalizeLabel(job.airframe_scope) === normalizeLabel(seeker.airframe_scope)) {
      matchedCount++;
    }
  }

  if (totalCount === 0) {
    return 100;
  }
  return Math.floor((matchedCount * 100) / totalCount);
}

function hasCommonCertificate(
  jobCerts: string[] | null,
  seekerCerts: string[] | null,
): boolean {
  if (!jobCerts || jobCerts.length === 0) return true; // no requirement
  if (!seekerCerts || seekerCerts.length === 0) return false;
  const seekerSet = new Set(seekerCerts.map((c) => c.toLowerCase()));
  return jobCerts.some((c) => seekerSet.has(c.toLowerCase()));
}

function stateInLocation(location: string | null, state: string | null): boolean {
  if (!state || state.trim() === "") return true;
  if (!location) return false;
  return location.toLowerCase().includes(state.toLowerCase());
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

    let payload: Payload = {};
    try {
      payload = (await req.json()) as Payload;
    } catch (_) {
      // Use default payload.
    }

    const isTest = payload.test === true;
    const seekerUserId = payload.seekerUserId?.trim() ?? "";
    const hoursBack =
      typeof payload.hoursBack === "number" && payload.hoursBack > 0
        ? payload.hoursBack
        : 24;

    const admin = createClient(supabaseUrl, serviceRoleKey);

    const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
    const emailFrom = Deno.env.get("EMAIL_FROM") ?? "";

    if (!resendApiKey || !emailFrom) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "RESEND_API_KEY or EMAIL_FROM not configured" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (isTest) {
      if (!seekerUserId) {
        return new Response(
          JSON.stringify({ error: "Missing seekerUserId for test mode" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const { data: seekerRow, error: seekerError } = await admin
        .from("job_seeker_profiles")
        .select(
          "user_id, email, state_or_province, airframe_scope, faa_certificates, " +
            "new_job_alert_enabled, new_job_alert_state_only, new_job_alert_airframe_match, " +
            "new_job_alert_minimum_match_percent, new_job_alert_certificate_match",
        )
        .eq("user_id", seekerUserId)
        .maybeSingle();

      if (seekerError) {
        return new Response(
          JSON.stringify({ error: `Failed to load seeker profile: ${seekerError.message}` }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      if (!seekerRow) {
        return new Response(
          JSON.stringify({ skipped: true, reason: "No seeker profile found for current user" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const seeker = seekerRow as SeekerRow;
      const email = seeker.email?.trim() ?? "";
      if (!email) {
        return new Response(
          JSON.stringify({ skipped: true, reason: "No seeker email available in profile" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const criteriaLines = [
        `Alerts enabled: ${seeker.new_job_alert_enabled ? "Yes" : "No"}`,
        `State/Region only: ${seeker.new_job_alert_state_only ? "Yes" : "No"}`,
        `Minimum profile match: ${Math.max(0, Math.min(100, seeker.new_job_alert_minimum_match_percent ?? 100))}%`,
        `Certificate match required: ${seeker.new_job_alert_certificate_match ? "Yes" : "No"}`,
      ];

      const html = `
        <h2>Job Alert Test Email</h2>
        <p>This is a temporary pre-launch test from your Job Seeker notification settings.</p>
        <p><strong>Current Settings:</strong></p>
        <ul>
          ${criteriaLines.map((line) => `<li>${line}</li>`).join("")}
        </ul>
        <p style="color:#666;font-size:13px;margin-top:20px;">
          This button is intended for testing and can be removed before go-live.
        </p>
      `;

      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: emailFrom,
          to: [email],
          subject: "Test: Job Seeker Notification Settings",
          html,
        }),
      });

      if (!response.ok) {
        const body = await response.text();
        return new Response(
          JSON.stringify({ error: `Resend failed: ${body}` }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      return new Response(
        JSON.stringify({ success: true, reason: "Seeker test email sent" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const since = new Date(Date.now() - hoursBack * 60 * 60 * 1000).toISOString();

    // Fetch new active jobs posted since the look-back window.
    const { data: newJobs, error: jobsError } = await admin
      .from("job_listings")
      .select(
        "id, title, company, location, airframe_scope, faa_certificates, required_ratings, " +
          "flight_hours, preferred_flight_hours, instructor_hours, preferred_instructor_hours, " +
          "specialty_hours, preferred_specialty_hours, status",
      )
      .eq("status", "active")
      .gte("created_at", since);

    if (jobsError) {
      return new Response(
        JSON.stringify({ error: `Failed to load jobs: ${jobsError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!newJobs || newJobs.length === 0) {
      return new Response(
        JSON.stringify({ success: true, sent: 0, reason: "No new jobs in window" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Fetch all seekers with job alerts enabled.
    const { data: seekers, error: seekersError } = await admin
      .from("job_seeker_profiles")
      .select(
        "user_id, email, state_or_province, airframe_scope, faa_certificates, type_ratings, " +
          "flight_hours, flight_hours_types, specialty_flight_hours_map, specialty_flight_hours, " +
          "new_job_alert_state_only, new_job_alert_airframe_match, " +
          "new_job_alert_minimum_match_percent, new_job_alert_certificate_match",
      )
      .eq("new_job_alert_enabled", true);

    if (seekersError) {
      return new Response(
        JSON.stringify({ error: `Failed to load seekers: ${seekersError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!seekers || seekers.length === 0) {
      return new Response(
        JSON.stringify({ success: true, sent: 0, reason: "No seekers with alerts enabled" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let sent = 0;
    let skipped = 0;

    for (const seeker of seekers as SeekerRow[]) {
      const email = seeker.email?.trim();
      if (!email) {
        skipped++;
        continue;
      }

      // Filter the new jobs to only those matching this seeker's criteria.
      const matchingJobs = (newJobs as JobRow[]).filter((job) => {
        if (seeker.new_job_alert_state_only) {
          if (!stateInLocation(job.location, seeker.state_or_province)) return false;
        }
        if (seeker.new_job_alert_certificate_match) {
          if (!hasCommonCertificate(job.faa_certificates, seeker.faa_certificates)) return false;
        }
        const minMatch = Math.max(
          0,
          Math.min(100, seeker.new_job_alert_minimum_match_percent ?? 100),
        );
        const matchPercent = evaluateJobMatchPercent(job, seeker);
        if (matchPercent < minMatch) {
          return false;
        }
        return true;
      });

      if (matchingJobs.length === 0) {
        skipped++;
        continue;
      }

      const jobListHtml = matchingJobs
        .map(
          (j) => {
            const matchPercent = evaluateJobMatchPercent(j, seeker);
            return (
            `<li style="margin-bottom: 8px;">
              <strong>${j.title}</strong> — ${j.company}
              <br><span style="color:#1f2937;font-size:12px;">Match: ${matchPercent}%</span>
              ${j.location ? `<br><span style="color:#666;font-size:13px;">${j.location}</span>` : ""}
            </li>`
            );
          },
        )
        .join("");

      const criteriaDesc: string[] = [];
      if (seeker.new_job_alert_state_only) criteriaDesc.push("in your state");
      criteriaDesc.push(
        `with at least ${Math.max(0, Math.min(100, seeker.new_job_alert_minimum_match_percent ?? 100))}% profile match`,
      );
      if (seeker.new_job_alert_certificate_match) criteriaDesc.push("matching your certificates");
      const criteriaNote =
        criteriaDesc.length > 0
          ? `These results are filtered to jobs ${criteriaDesc.join(" and ")}.`
          : "These are all new listings posted on the platform.";

      const html = `
        <h2>${matchingJobs.length} New Aviation Job${matchingJobs.length === 1 ? "" : "s"} Posted</h2>
        <p>${criteriaNote}</p>
        <ul style="padding-left: 20px;">${jobListHtml}</ul>
        <p style="margin-top: 24px;">
          <a href="${supabaseUrl.replace("supabase.co", "").replace("https://", "")}">
            Open the app to view details and apply.
          </a>
        </p>
        <p style="color:#666;font-size:13px;margin-top:24px;">
          You are receiving this because you have new job alerts enabled in your job seeker profile.
          You can turn these off in your profile notification settings.
        </p>
      `;

      try {
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${resendApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from: emailFrom,
            to: [email],
            subject: `${matchingJobs.length} new aviation job${matchingJobs.length === 1 ? "" : "s"} matching your preferences`,
            html,
          }),
        });
        if (response.ok) {
          sent++;
        } else {
          skipped++;
        }
      } catch (_) {
        skipped++;
      }
    }

    return new Response(
      JSON.stringify({ success: true, sent, skipped, newJobCount: newJobs.length }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: `Unhandled function error: ${String(error)}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
