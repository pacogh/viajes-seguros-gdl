import {redirect} from "next/navigation";import {getSession} from "@/lib/auth/sessions";import {AppFrame} from "@/components/app-frame";
export default async function PassengerLayout({children}:{children:React.ReactNode}){const u=await getSession();if(!u)redirect("/login");if(u.role!=="passenger")redirect("/admin");return <AppFrame name={u.full_name}>{children}</AppFrame>}
