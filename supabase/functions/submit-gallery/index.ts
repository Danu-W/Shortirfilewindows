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
    const body = await req.json();
    const galleryId = String(body.gallery_id || "");
    const files = Array.isArray(body.files) ? body.files : [];
    const clientName = String(body.client_name || "");

    if (!galleryId || !Array.isArray(files) || files.length === 0) {
      return new Response(JSON.stringify({ error: "gallery_id dan files wajib diisi" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SERVICE_ROLE_KEY")!,
    );

    const { data: gallery, error: galleryError } = await supabase
      .from("galleries")
      .select("id, expires_at")
      .eq("id", galleryId)
      .maybeSingle();

    if (galleryError || !gallery) {
      return new Response(JSON.stringify({ error: "Gallery does not exist" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (gallery.expires_at && new Date(gallery.expires_at).getTime() < Date.now()) {
      return new Response(JSON.stringify({ error: "Galeri telah kedaluwarsa" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { error: insertError } = await supabase
      .from("gallery_submissions")
      .insert({ gallery_id: galleryId, client_name: clientName, files });

    if (insertError) {
      return new Response(JSON.stringify({ error: insertError.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ ok: true, count: files.length }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
