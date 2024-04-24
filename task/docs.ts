import { BuildInfo } from 'hardhat/types'
import { task } from 'hardhat/config'
import { docgen } from 'solidity-docgen'

task('utils:gen-docs', 'Generate docs from contract interface').setAction(async (_, hre) => {
  await hre.run('compile')

  const { promises: fs } = await import('fs')
  const buildInfoPaths = await hre.artifacts.getBuildInfoPaths()
  const builds = await Promise.all(
    buildInfoPaths.map(async (p) => ({
      mtime: (await fs.stat(p)).mtimeMs,
      data: JSON.parse(await fs.readFile(p, 'utf8')) as BuildInfo,
    })),
  )

  // Sort most recently modified first
  builds.sort((a, b) => b.mtime - a.mtime)

  await docgen(
    builds.map((b) => b.data),
    {
      templates: 'docgen-templates',
      sourcesDir: 'contracts/interfaces',
      pages: 'files',
    },
  )
})
