import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function midtransBaseUrl(): string {
  return Deno.env.get("MIDTRANS_ENVIRONMENT") === "production"
    ? "https://api.midtrans.com"
    : "https://api.sandbox.midtrans.com";
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authorization = req.headers.get("Authorization") ?? "";
    const token = authorization.replace(/^Bearer\s+/i, "").trim();
    if (!token) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "",
    );
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token);
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const serverKey = Deno.env.get("MIDTRANS_SERVER_KEY");
    if (!serverKey) {
      return new Response(JSON.stringify({ error: "Midtrans is not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json().catch(() => ({}));
    const amount = Number(body.amount ?? Deno.env.get("MIDTRANS_PRO_AMOUNT") ?? "15000");
    const plan = body.plan === "yearly" ? "yearly" : "monthly";
    const description = typeof body.description === "string"
      ? body.description
      : `Shortir File Pro ${plan}`;
    const expectedAmount = plan === "yearly" ? 150000 : 15000;
    if (amount !== expectedAmount) {
      return new Response(JSON.stringify({ error: "Invalid plan amount" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const orderId = `${user.id}_${plan}_${Date.now()}`;
    const auth = btoa(`${serverKey}:`);
    const chargeController = new AbortController();
    const chargeTimeout = setTimeout(() => chargeController.abort(), 15000);
    let response: Response;
    try {
      response = await fetch(`${midtransBaseUrl()}/v2/charge`, {
        method: "POST",
        headers: {
          Authorization: `Basic ${auth}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        signal: chargeController.signal,
        body: JSON.stringify({
        payment_type: "qris",
        transaction_details: {
          order_id: orderId,
          gross_amount: amount,
        },
        customer_details: {
          email: user.email ?? undefined,
        },
        custom_expiry: {
          expiry_duration: 30,
          unit: "minute",
        },
          metadata: { description },
        }),
      });
    } finally {
      clearTimeout(chargeTimeout);
    }
    const transaction = await response.json();
    if (!response.ok) {
      return new Response(JSON.stringify({ error: transaction }), {
        status: response.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const qrAction = Array.isArray(transaction.actions)
      ? transaction.actions.find((action: { name?: string }) => action.name === "generate-qr-code")
      : null;
    const qrUrl = qrAction?.url;
    if (typeof qrUrl !== "string" || qrUrl.length === 0) {
      return new Response(JSON.stringify({ error: "Midtrans did not return a QR code" }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const qrController = new AbortController();
    const qrTimeout = setTimeout(() => qrController.abort(), 10000);
    let qrResponse: Response;
    try {
      qrResponse = await fetch(qrUrl, {
        headers: { Authorization: `Basic ${auth}`, Accept: "image/png" },
        signal: qrController.signal,
      });
    } finally {
      clearTimeout(qrTimeout);
    }
    if (!qrResponse.ok) {
      const qrError = await qrResponse.text();
      return new Response(JSON.stringify({
        error: "Unable to fetch QR code",
        midtrans_status: qrResponse.status,
        midtrans_response: qrError.slice(0, 500),
      }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const qrBytes = new Uint8Array(await qrResponse.arrayBuffer());
    let binary = "";
    for (const byte of qrBytes) binary += String.fromCharCode(byte);
    const qrBase64 = btoa(binary);

    return new Response(JSON.stringify({
      qr_base64: qrBase64,
      qr_content_type: qrResponse.headers.get("content-type") ?? "image/png",
      order_id: orderId,
      expires_at: transaction.expiry_time ?? null,
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
