import type { Metadata } from "next";
import "./globals.css";
export const metadata:Metadata={title:"Viaje Seguro GDL",description:"Solicita y administra viajes en el Área Metropolitana de Guadalajara"};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="es"><body>{children}</body></html>}
