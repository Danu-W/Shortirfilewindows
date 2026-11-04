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
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
    const client = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "",
    );
    const { data: { user } } = await client.auth.getUser(token);
    if (!user) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    const body = await req.json().catch(() => ({}));
    const orderId = typeof body.order_id === "string" ? body.order_id : "";
    if (!orderId || !orderId.startsWith(`${user.id}_`)) return new Response(JSON.stringify({ error: "Invalid order" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    const serverKey = Deno.env.get("MIDTRANS_SERVER_KEY");
    if (!serverKey) return new Response(JSON.stringify({ error: "Midtrans is not configured" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    const response = await fetch(`${midtransBaseUrl()}/v2/${encodeURIComponent(orderId)}/status`, { headers: { Authorization: `Basic ${btoa(`${serverKey}:`)}`, Accept: "application/json" } });
    const transaction = await response.json();
    if (!response.ok) return new Response(JSON.stringify({ error: transaction }), { status: response.status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    return new Response(JSON.stringify({ order_id: orderId, transaction_status: transaction.transaction_status, fraud_status: transaction.fraud_status ?? null, gross_amount: transaction.gross_amount }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
