import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function midtransBaseUrl(): string {
  return Deno.env.get("MIDTRANS_ENVIRONMENT") === "production"
    ? "https://api.midtrans.com"
    : "https://api.sandbox.midtrans.com";
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  try {
    const body = await req.json();
    const orderId = typeof body.order_id === "string" ? body.order_id : "";
    const statusCode = typeof body.status_code === "string" ? body.status_code : "";
    const grossAmount = typeof body.gross_amount === "string"
      ? body.gross_amount
      : String(body.gross_amount ?? "");
    const signatureKey = typeof body.signature_key === "string" ? body.signature_key : "";
    const serverKey = Deno.env.get("MIDTRANS_SERVER_KEY");
    const amountPlans: Record<number, { productId: string; months: number }> = {
    99000: { productId: "shortir_file_pro_monthly", months: 1 },
    15000: { productId: "shortir_file_pro_monthly", months: 1 },
    150000: { productId: "shortir_file_pro_yearly", months: 12 },
  };
    if (!serverKey || !orderId || !signatureKey) {
      return new Response("Webhook is not configured", { status: 500 });
    }

    const signaturePayload = `${orderId}${statusCode}${grossAmount}${serverKey}`;
    const signatureBytes = await crypto.subtle.digest(
      "SHA-512",
      new TextEncoder().encode(signaturePayload),
    );
    const expectedSignature = [...new Uint8Array(signatureBytes)]
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("");
    if (signatureKey.toLowerCase() !== expectedSignature) {
      return new Response("Invalid signature", { status: 401 });
    }

    const userId = orderId.split("_")[0];
    const plan = amountPlans[Number(grossAmount)];
    if (!/^[0-9a-f-]{36}$/i.test(userId) || !plan) {
      return new Response("Invalid order payload", { status: 400 });
    }

    const statusResponse = await fetch(
      `${midtransBaseUrl()}/v2/${encodeURIComponent(orderId)}/status`,
      { headers: { Authorization: `Basic ${btoa(`${serverKey}:`)}` } },
    );
    if (!statusResponse.ok) {
      return new Response("Could not verify transaction", { status: 502 });
    }
    const transaction = await statusResponse.json();
    const paid = transaction.transaction_status === "settlement" ||
      (transaction.transaction_status === "capture" && transaction.fraud_status === "accept");
    if (!paid || Number(transaction.gross_amount) !== Number(grossAmount)) {
      return new Response("Payment not settled", { status: 200 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return new Response("Supabase webhook is not configured", { status: 500 });
    }
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);
    const { error } = await supabaseAdmin.from("billing_entitlements").upsert({
      user_id: userId,
      entitlement: "pro",
      status: "active",
      provider: "midtrans",
      product_id: plan.productId,
      expires_at: new Date(Date.now() + plan.months * 30 * 24 * 60 * 60 * 1000).toISOString(),
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });
    if (error) throw error;

    return new Response("ok", { status: 200 });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: message }), { status: 500 });
  }
});
