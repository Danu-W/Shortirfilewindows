import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  try {
    const expectedToken = Deno.env.get("XENDIT_WEBHOOK_TOKEN");
    const callbackToken = req.headers.get("x-callback-token");
    if (!expectedToken || callbackToken !== expectedToken) {
      return new Response("Unauthorized", { status: 401 });
    }

    const body = await req.json();
    const status = typeof body.status === "string" ? body.status.toUpperCase() : "";
    const externalId = typeof body.external_id === "string" ? body.external_id : "";
    const invoiceId = typeof body.id === "string" ? body.id : "";

    if (status === "PAID" || status === "SETTLED") {
      if (!externalId || !/^[0-9a-f-]{36}$/i.test(externalId) || !invoiceId) {
        return new Response("Invalid invoice payload", { status: 400 });
      }

      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const serviceRoleKey =
        Deno.env.get("SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      const xenditSecret = Deno.env.get("XENDIT_SECRET_KEY");
      if (!supabaseUrl || !serviceRoleKey || !xenditSecret) {
        return new Response("Webhook is not configured", { status: 500 });
      }

      const invoiceResponse = await fetch(
        `https://api.xendit.co/v2/invoices/${encodeURIComponent(invoiceId)}`,
        {
          headers: {
            Authorization: `Basic ${btoa(`${xenditSecret}:`)}`,
          },
        }
      );
      if (!invoiceResponse.ok) {
        return new Response("Could not verify invoice", { status: 502 });
      }

      const invoice = await invoiceResponse.json();
      const expectedAmount = Number(Deno.env.get("XENDIT_PRO_AMOUNT") ?? "99000");
      const invoiceStatus =
        typeof invoice.status === "string" ? invoice.status.toUpperCase() : "";
      if (
        invoice.external_id !== externalId ||
        !["PAID", "SETTLED"].includes(invoiceStatus) ||
        Number(invoice.amount) !== expectedAmount
      ) {
        return new Response("Invoice verification failed", { status: 400 });
      }

      const supabaseAdmin = createClient(
        supabaseUrl,
        serviceRoleKey
      );

      const { error } = await supabaseAdmin.from("billing_entitlements").upsert(
        {
          user_id: externalId,
          entitlement: "pro",
          status: "active",
          provider: "xendit",
          product_id: "shortir_file_pro",
          expires_at: null,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id" }
      );
      if (error) {
        throw error;
      }

      return new Response("ok", { status: 200 });
    }

    return new Response("ignored", { status: 200 });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ error: message }), { status: 500 });
  }
});
