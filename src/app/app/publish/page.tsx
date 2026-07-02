"use client";

import { useRef, useState } from "react";
import Link from "next/link";
import { QRCodeSVG } from "qrcode.react";
import { Body, Button, Caption } from "@breadcoop/ui";
import {
  ArrowRight,
  Check,
  CloudArrowUp,
  Copy,
  FolderOpen,
  Globe,
  SpinnerGap,
  Warning,
} from "@phosphor-icons/react";
import { Card, PageHeader } from "@/components/dapp/ui";
import {
  canSelfPin,
  collectSelfFiles,
  filesFromFolderInput,
  ipfsUrls,
} from "@/lib/ipfs";
import { copyToClipboard, cn } from "@/lib/utils";
import { ENS_HOST } from "@/lib/constants";

type Step =
  | "idle"
  | "collecting"
  | "awaiting-email"
  | "provisioning"
  | "uploading"
  | "done"
  | "error";

export default function PublishPage() {
  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader
        title="Publish to IPFS"
        subtitle="Pin this app to IPFS from your browser — no CI, no keys in a repo. You get a content-addressed copy that every instance can be served from, censorship-resistant."
      />
      <Publish />
    </div>
  );
}

function CopyBtn({
  text,
  label,
  copiedKey,
  onCopy,
}: {
  text: string;
  label: string;
  copiedKey: string;
  onCopy: (text: string, key: string) => void;
}) {
  const isCopied = copiedKey === label;
  return (
    <button
      onClick={() => onCopy(text, label)}
      aria-label={`Copy ${label}`}
      className={cn(
        "flex flex-none items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-semibold text-white",
        isCopied ? "bg-system-green" : "bg-core-orange",
      )}
    >
      {isCopied ? (
        <>
          <Check size={16} weight="bold" /> Copied
        </>
      ) : (
        <>
          <Copy size={16} /> Copy
        </>
      )}
    </button>
  );
}

function UrlRow({
  label,
  url,
  copiedKey,
  onCopy,
}: {
  label: string;
  url: string;
  copiedKey: string;
  onCopy: (text: string, key: string) => void;
}) {
  return (
    <div className="mt-3">
      <Caption className="text-surface-grey-2 font-semibold">{label}</Caption>
      <div className="mt-1 flex items-center gap-2">
        <input
          readOnly
          value={url}
          onFocus={(e) => e.currentTarget.select()}
          className="border-paper-2 bg-paper-main text-text-standard w-full rounded-lg border px-2.5 py-2 font-mono text-xs outline-none"
        />
        <CopyBtn
          text={url}
          label={label}
          copiedKey={copiedKey}
          onCopy={onCopy}
        />
      </div>
    </div>
  );
}

function Publish() {
  const [source, setSource] = useState<"self" | "folder">(
    canSelfPin ? "self" : "folder",
  );
  const [folder, setFolder] = useState<File[]>([]);
  const [email, setEmail] = useState("");
  const [step, setStep] = useState<Step>("idle");
  const [progress, setProgress] = useState({ done: 0, total: 0 });
  const [cid, setCid] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState<string | null>(null);
  const abortRef = useRef<AbortController | null>(null);

  const busy =
    step === "collecting" ||
    step === "awaiting-email" ||
    step === "provisioning" ||
    step === "uploading";

  const onCopy = async (text: string, key: string) => {
    if (await copyToClipboard(text)) {
      setCopied(key);
      setTimeout(() => setCopied(null), 1600);
    }
  };

  const publish = async () => {
    setError(null);
    setCid(null);
    // So each failure says which phase broke — the upload path can't be
    // exercised in tests (needs a live Storacha account), so error context
    // is the debugging story.
    let phase = "Preparing";
    const abort = new AbortController();
    abortRef.current = abort;
    try {
      // 1. Gather the files to pin.
      phase = "Gathering files";
      setStep("collecting");
      const files =
        source === "self"
          ? await collectSelfFiles((done, total) =>
              setProgress({ done, total }),
            )
          : folder;
      if (files.length === 0) {
        throw new Error(
          source === "folder"
            ? "Choose your out/ folder first."
            : "No files to publish.",
        );
      }
      // The gather loop doesn't take the abort signal — honor a cancel here.
      if (abort.signal.aborted) throw new Error("Cancelled");

      // 2. Storacha browser client — lazy-loaded so it never bloats other pages.
      phase = "Starting the uploader";
      const Client = await import("@storacha/client");
      const client = await Client.create();

      // 3. Reuse an existing space, else sign in by email and create one.
      let spaceDid = client.spaces()[0]?.did();
      if (!spaceDid) {
        if (!email.includes("@")) {
          throw new Error("Enter your email to sign in to Storacha.");
        }
        phase = "Signing in";
        setStep("awaiting-email");
        const account = await client.login(email as `${string}@${string}`, {
          signal: abort.signal,
        });
        // On the free plan the plan is chosen via the same email link; wait
        // for it so createSpace doesn't fail on an unprovisioned account.
        try {
          await account.plan.wait({ signal: abort.signal });
        } catch {
          /* best-effort — plan may already be selected */
        }
        phase = "Creating your storage space";
        setStep("provisioning");
        const space = await client.createSpace("crowdstake", { account });
        spaceDid = space.did();
      }
      phase = "Selecting your storage space";
      await client.setCurrentSpace(spaceDid);

      // 4. Upload the directory → root CID.
      phase = "Uploading";
      setStep("uploading");
      const root = await client.uploadDirectory(files, {
        signal: abort.signal,
      });
      setCid(root.toString());
      setStep("done");
    } catch (e) {
      if (abort.signal.aborted) {
        // User cancelled — back to a clean slate, not an error.
        setStep("idle");
        return;
      }
      const msg = e instanceof Error ? e.message : String(e);
      setError(`${phase} failed: ${msg}`);
      setStep("error");
    } finally {
      abortRef.current = null;
    }
  };

  if (step === "done" && cid) {
    const urls = ipfsUrls(cid);
    return (
      <Card>
        <p className="text-system-green flex items-center gap-2">
          <Check size={22} weight="bold" />
          <span className="font-breadDisplay text-lg font-bold">
            Published to IPFS
          </span>
        </p>
        <Body className="text-surface-grey-2 mt-1 text-sm">
          Your app is now content-addressed. Append{" "}
          <code className="text-text-standard">?i=&lt;instance&gt;</code> to any
          of these to open a specific instance.
        </Body>

        <UrlRow
          label="dweb.link"
          url={urls.dweb}
          copiedKey={copied ?? ""}
          onCopy={onCopy}
        />
        <UrlRow
          label="w3s.link"
          url={urls.w3s}
          copiedKey={copied ?? ""}
          onCopy={onCopy}
        />

        <div className="border-paper-2 mt-4 flex items-start gap-4 rounded-xl border p-4">
          <div className="min-w-0 flex-1">
            <Caption className="text-text-standard font-semibold">
              Make it permanent with ENS
            </Caption>
            <Body className="text-surface-grey-2 mt-1 text-sm">
              Point your ENS name&apos;s <b>content hash</b> at the URI below
              (one mainnet transaction in the ENS app). Then it&apos;s live at{" "}
              <span className="font-mono">
                {ENS_HOST ? `${ENS_HOST}.limo` : "<name>.eth.limo"}/app/
              </span>
              .
            </Body>
            <UrlRow
              label="ipfs://"
              url={urls.ipfsUri}
              copiedKey={copied ?? ""}
              onCopy={onCopy}
            />
          </div>
          <div className="hidden shrink-0 flex-col items-center sm:flex">
            <div className="border-paper-2 rounded-lg border bg-white p-2">
              <QRCodeSVG value={urls.dweb} size={112} marginSize={2} />
            </div>
            <Caption className="text-surface-grey mt-1 block text-center text-[11px]">
              Scan to open
            </Caption>
          </div>
        </div>

        <div className="mt-6 flex flex-wrap gap-3">
          <Button
            app="fund"
            variant="secondary"
            onClick={() => {
              setStep("idle");
              setCid(null);
            }}
          >
            Publish again
          </Button>
          <Button
            app="fund"
            variant="primary"
            as={Link}
            href="/app"
            rightIcon={<ArrowRight weight="bold" />}
          >
            Back to app
          </Button>
        </div>
      </Card>
    );
  }

  return (
    <Card>
      {/* Source */}
      <Caption className="text-surface-grey-2 font-semibold">
        What to publish
      </Caption>
      <div className="mt-2 grid gap-2 sm:grid-cols-2">
        <button
          disabled={!canSelfPin || busy}
          onClick={() => setSource("self")}
          className={cn(
            "flex items-start gap-2 rounded-xl border p-3 text-left",
            source === "self"
              ? "border-core-orange bg-core-orange/5"
              : "border-paper-2 hover:border-core-orange/50",
            !canSelfPin && "cursor-not-allowed opacity-50",
          )}
        >
          <Globe size={20} className="text-core-orange mt-0.5 flex-none" />
          <span>
            <span className="text-text-standard block text-sm font-semibold">
              This running app
            </span>
            <Caption className="text-surface-grey-2">
              Re-pins the exact site you&apos;re viewing.
            </Caption>
          </span>
        </button>
        <button
          disabled={busy}
          onClick={() => setSource("folder")}
          className={cn(
            "flex items-start gap-2 rounded-xl border p-3 text-left",
            source === "folder"
              ? "border-core-orange bg-core-orange/5"
              : "border-paper-2 hover:border-core-orange/50",
          )}
        >
          <FolderOpen size={20} className="text-core-orange mt-0.5 flex-none" />
          <span>
            <span className="text-text-standard block text-sm font-semibold">
              Upload a folder
            </span>
            <Caption className="text-surface-grey-2">
              Your local <code>pnpm build:ipfs</code> → <code>out/</code>.
            </Caption>
          </span>
        </button>
      </div>

      {!canSelfPin && (
        <Caption className="text-system-warning mt-2 flex items-center gap-1.5">
          <Warning size={14} weight="fill" />
          This build is served from a subpath, so it can&apos;t re-pin itself —
          upload a folder built with <code>pnpm build:ipfs</code>.
        </Caption>
      )}

      {source === "folder" && (
        <div className="mt-3">
          {/* webkitdirectory lets the user pick a whole folder */}
          <input
            type="file"
            /* @ts-expect-error non-standard but widely supported directory attrs */
            webkitdirectory=""
            directory=""
            multiple
            disabled={busy}
            onChange={(e) => {
              setError(null);
              try {
                setFolder(filesFromFolderInput(e.target.files));
              } catch (err) {
                setFolder([]);
                setError(err instanceof Error ? err.message : String(err));
              }
            }}
            className="text-surface-grey-2 block w-full text-sm disabled:opacity-60"
          />
          {folder.length > 0 && (
            <Caption className="text-surface-grey mt-1">
              {folder.length} files selected
            </Caption>
          )}
        </div>
      )}

      {/* Email (Storacha sign-in) */}
      <div className="mt-5">
        <Caption className="text-surface-grey-2 font-semibold">
          Storacha email
        </Caption>
        <Body className="text-surface-grey-2 mt-1 text-sm">
          Needed the first time on this device — we email you a link to confirm;
          no password, no token to paste. Already published here before?
          You&apos;re signed in and can leave this empty. Storacha stores the
          bytes on IPFS + Filecoin (free tier).
        </Body>
        <input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@example.com"
          disabled={busy}
          className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange mt-2 w-full rounded-lg border px-3 py-2 text-sm outline-none disabled:opacity-60"
        />
      </div>

      <div className="mt-6">
        <Button
          app="fund"
          variant="primary"
          className="w-full"
          disabled={busy}
          onClick={publish}
          leftIcon={
            busy ? (
              <SpinnerGap className="animate-spin" weight="bold" />
            ) : (
              <CloudArrowUp weight="bold" />
            )
          }
        >
          {busy ? "Publishing…" : "Publish to IPFS"}
        </Button>
      </div>

      {busy && (
        <div className="mt-3 flex items-center justify-between gap-3">
          <Caption className="text-surface-grey-2 block">
            {step === "collecting" &&
              `Gathering the app files… ${progress.done}/${progress.total}`}
            {step === "awaiting-email" &&
              "Check your email and click the Storacha link to continue…"}
            {step === "provisioning" && "Setting up your storage space…"}
            {step === "uploading" && "Uploading to IPFS…"}
          </Caption>
          <button
            onClick={() => abortRef.current?.abort()}
            className="text-surface-grey-2 hover:text-system-red flex-none text-sm font-medium underline-offset-2 hover:underline"
          >
            Cancel
          </button>
        </div>
      )}

      {error && (
        <Caption className="text-system-red mt-3 flex items-start gap-1.5">
          <Warning size={14} weight="fill" className="mt-0.5 flex-none" />
          {error}
        </Caption>
      )}
    </Card>
  );
}
