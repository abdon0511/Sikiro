// Supabase Edge Function: envía un correo con Resend cuando llega un contacto
// Desplegar: supabase functions deploy send-contact-email
// Secrets necesarios (Supabase Dashboard > Edge Functions > Secrets):
//   RESEND_API_KEY = re_... (de resend.com)
//   CONTACT_TO_EMAIL = correos separados por coma (ej: a@gmail.com,b@gmail.com,c@gmail.com)
//   CONTACT_FROM_EMAIL = onboarding@resend.dev (pruebas) o tu dominio verificado

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { name, email, message } = await req.json();
    if (!name || !email || !message) throw new Error("Faltan datos");
    if (String(message).length > 500) throw new Error("Mensaje muy largo");

    const toEmails = (Deno.env.get("CONTACT_TO_EMAIL") || "").split(",").map((e) => e.trim()).filter(Boolean);
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: Deno.env.get("CONTACT_FROM_EMAIL") || "Sikiro <onboarding@resend.dev>",
        to: toEmails,
        reply_to: email,
        subject: `Nuevo contacto Sikiro: ${name}`,
        text: `Nombre: ${name}\nCorreo: ${email}\n\n${message}`,
      }),
    });
    if (!res.ok) throw new Error("Resend error: " + (await res.text()));
    return new Response(JSON.stringify({ ok: true }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
