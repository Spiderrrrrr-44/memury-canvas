import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Memury — Learning in context",
  description:
    "A Canvas-native learning agent with document-grounded Q Graph conversations, explainable planning, and verified learning memory.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
  openGraph: {
    title: "Memury — Learning in context",
    description:
      "Document-grounded Q Graph conversations, explainable planning, and verified learning memory inside Canvas.",
    images: ["/memury-social.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
