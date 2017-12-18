module.exports = {
  servers: {
    one: {
      host: 'coauthor.ulb.ac.be',
      username: 'meteorapp'
    }
  },

  meteor: {
    name: 'coauthor',
    path: '.',
    servers: {
      one: {}
    },
    docker: {
      image: 'abernix/meteord:node-8.4.0-base'
    },
    buildOptions: {
      serverOnly: true
    },
    env: {
      ROOT_URL: 'https://coauthor.ulb.ac.be',
      PORT: 3001,
      MAIL_URL: 'smtp://smtp.ulb.ac.be:25?ignoreTLS=true'
    },
    deployCheckWaitTime: 30,
    deployCheckPort: 80,
    enableUploadProgressBar: true
  },

  mongo: {
    oplog: true,
    port: 27017,
    servers: {
      one: {},
    },
  },

  // Run 'npm install' before deploying, to ensure packages are up-to-date
  hooks: {
    'pre.deploy': {
      localCommand: 'npm install'
    }
  },
};
