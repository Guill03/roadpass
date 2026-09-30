import { withSupabase } from 'npm:@supabase/server'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

export default {
    fetch: withSupabase({ auth: 'user' }, async (request, context) => {
        if (request.method === 'OPTIONS') {
            return new Response('ok', { headers: corsHeaders })
        }

        if (request.method !== 'POST') {
            return Response.json(
                { message: 'Méthode non autorisée.' },
                { status: 405, headers: corsHeaders },
            )
        }

        const { data: authData, error: authError } = await context.supabase.auth.getUser()
        if (authError || !authData.user) {
            return Response.json(
                { message: 'Session administrateur invalide.' },
                { status: 401, headers: corsHeaders },
            )
        }

        const { data: adminProfile, error: profileError } = await context.supabase
            .from('profiles')
            .select('role')
            .eq('id', authData.user.id)
            .maybeSingle()

        if (profileError || adminProfile?.role !== 'admin') {
            return Response.json(
                { message: 'Seul un administrateur peut créer un agent.' },
                { status: 403, headers: corsHeaders },
            )
        }

        let body: Record<string, unknown>
        try {
            body = await request.json()
        } catch (_) {
            return Response.json(
                { message: 'Le corps de la requête est invalide.' },
                { status: 400, headers: corsHeaders },
            )
        }
        const nom = String(body.nom ?? '').trim()
        const prenom = String(body.prenom ?? '').trim()
        const email = String(body.email ?? '').trim().toLowerCase()
        const telephone = String(body.telephone ?? '').trim()
        const password = String(body.password ?? '')

        if (
            !nom ||
            !prenom ||
            !/^\S+@\S+\.\S+$/.test(email) ||
            !telephone ||
            password.length < 8
        ) {
            return Response.json(
                { message: 'Les informations de création sont invalides.' },
                { status: 400, headers: corsHeaders },
            )
        }

        const { data: createdUser, error: createError } =
            await context.supabaseAdmin.auth.admin.createUser({
                email,
                password,
                email_confirm: true,
                user_metadata: {
                    nom,
                    prenom,
                    telephone,
                },
            })

        if (createError || !createdUser.user) {
            return Response.json(
                { message: createError?.message ?? 'La création du compte agent a échoué.' },
                { status: 400, headers: corsHeaders },
            )
        }

        const { error: profileUpdateError } = await context.supabaseAdmin
            .from('profiles')
            .update({ nom, prenom, telephone, email, role: 'agent' })
            .eq('id', createdUser.user.id)

        if (profileUpdateError) {
            await context.supabaseAdmin.auth.admin.deleteUser(createdUser.user.id)
            return Response.json(
                { message: 'Le profil agent n’a pas pu être créé.' },
                { status: 500, headers: corsHeaders },
            )
        }

        return Response.json(
            { id: createdUser.user.id },
            { status: 201, headers: corsHeaders },
        )
    }),
}
