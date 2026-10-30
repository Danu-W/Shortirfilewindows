import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: req.headers.get("Authorization")! } } }
    );

    const { data: { user } } = await supabaseClient.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { amount = 99000, description = "Shortir File Pro" } = await req.json().catch(() => ({}));
    const xenditSecret = Deno.env.get("XENDIT_SECRET_KEY");

    const invoiceRes = await fetch("https://api.xendit.co/v2/invoices", {
      method: "POST",
      headers: {
        "Authorization": "Basic " + btoa(xenditSecret + ":"),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        external_id: user.id,
        amount: amount,
        payer_email: user.email,
        description: description,
        currency: "IDR",
        success_redirect_url: "shortirfile://login-callback/",
        failure_redirect_url: "shortirfile://login-callback/",
      }),
    });

    const invoice = await invoiceRes.json();
    if (!invoiceRes.ok) {
      return new Response(JSON.stringify({ error: invoice.message || invoice }), {
        status: invoiceRes.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ invoice_url: invoice.invoice_url }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
