import React from 'react';
import Layout from '../components/Layout';
import MailSender from '../components/MailSender';

const MailPage: React.FC = () => {
  return (
    <Layout>
      <MailSender />
    </Layout>
  );
};

export default MailPage;
