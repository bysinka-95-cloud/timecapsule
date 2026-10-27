<?php
// File storage for capsule attachments.
//
// This is the only file that reads or writes uploaded files. They are kept in the S3 bucket
// S3_BUCKET under the "uploads/" prefix. The rest of the app only uses the three functions
// storage_save(), storage_delete() and storage_stream().
//
// There are no access keys here: the AWS SDK takes temporary credentials from the IAM role
// of the EC2 instance (timecapsule-dev-app-role).

use Aws\S3\S3Client;

// One S3 client per request, created on first use.
function s3_client(): S3Client
{
    static $client = null;
    return $client ??= new S3Client(['region' => config('AWS_REGION', 'eu-central-1')]);
}

function s3_bucket(): string
{
    $bucket = config('S3_BUCKET');
    if ($bucket === null) {
        throw new RuntimeException('S3_BUCKET is not set in .env.');
    }
    return $bucket;
}

// Object key of a stored file. basename() keeps every key under "uploads/".
function s3_key(string $storedName): string
{
    return 'uploads/' . basename($storedName);
}

// Save an uploaded file ($_FILES['...'] entry) and return its stored name, e.g. "3f9a...e1.png".
// The name is random, so users cannot guess other people's file names.
function storage_save(array $uploadedFile, string $extension): string
{
    $storedName = bin2hex(random_bytes(16)) . '.' . $extension;

    s3_client()->putObject([
        'Bucket'      => s3_bucket(),
        'Key'         => s3_key($storedName),
        'SourceFile'  => $uploadedFile['tmp_name'],
        'ContentType' => mime_content_type($uploadedFile['tmp_name']) ?: 'application/octet-stream',
    ]);
    return $storedName;
}

// With versioning on, this adds a delete marker; older versions stay until the lifecycle rule removes them.
function storage_delete(?string $storedName): void
{
    if ($storedName === null || $storedName === '') {
        return;
    }

    s3_client()->deleteObject([
        'Bucket' => s3_bucket(),
        'Key'    => s3_key($storedName),
    ]);
}

// Send the browser to the file: a 302 redirect to a presigned S3 URL that is valid for 5 minutes.
// The URL also tells S3 which Content-Type and Content-Disposition to send back.
// $disposition: "inline" (show in the browser) or "attachment" (download).
function storage_stream(string $storedName, string $mime, string $downloadName, string $disposition): void
{
    // Keep only safe characters for the plain filename; the UTF-8 name goes in filename*.
    $asciiName = preg_replace('/[^A-Za-z0-9._ -]/', '_', $downloadName);

    $command = s3_client()->getCommand('GetObject', [
        'Bucket'                     => s3_bucket(),
        'Key'                        => s3_key($storedName),
        'ResponseContentType'        => $mime,
        'ResponseContentDisposition' => sprintf(
            '%s; filename="%s"; filename*=UTF-8\'\'%s',
            $disposition,
            $asciiName,
            rawurlencode($downloadName)
        ),
    ]);
    $request = s3_client()->createPresignedRequest($command, '+5 minutes');

    redirect((string) $request->getUri());
}
